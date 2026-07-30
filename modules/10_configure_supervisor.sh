#!/usr/bin/env bash

supervisor_source_config() { printf '%s\n' "${BENCH_PATH}/config/supervisor.conf"; }

managed_supervisor_processes() {
  supervisorctl status 2>/dev/null | awk -v prefix="$BENCH_NAME" '$1 ~ ("^" prefix "([:-]|$)") {print $1, $2}'
}

managed_processes_running() {
  local output managed_count bad_count
  output="$(managed_supervisor_processes || true)"
  managed_count="$(sed '/^[[:space:]]*$/d' <<<"$output" | wc -l)"
  bad_count="$(awk '$2 != "RUNNING" {count++} END {print count + 0}' <<<"$output")"
  ((managed_count >= 5 && bad_count == 0))
}

recover_managed_processes() {
  local process state count=0
  while read -r process state; do
    [[ -n "$process" ]] || continue
    count=$((count + 1))
    if [[ "$state" == RUNNING ]]; then
      run_command "Restart Supervisor process ${process}" supervisorctl restart "$process"
    else
      run_command "Start Supervisor process ${process} (${state})" supervisorctl start "$process"
    fi
  done < <(managed_supervisor_processes)
  ((count > 0)) || return 1
}

wait_for_managed_processes() {
  local attempt
  for attempt in {1..15}; do
    managed_processes_running && return 0
    sleep 2
  done
  supervisorctl status >>"$LOG_FILE" 2>&1 || true
  return 1
}

ping_bench_redis() {
  local config port response
  while IFS= read -r config; do
    port="$(awk '$1 == "port" {print $2; exit}' "$config")"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    response="$(redis-cli --host 127.0.0.1 --port "$port" ping 2>/dev/null)"
    [[ "$response" == "PONG" ]] || return 1
  done < <(redis_config_files)
}

module_description() { printf '%s\n' "Configure Supervisor production processes"; }

module_check() {
  dpkg-query -W -f='${db:Status-Abbrev}' supervisor 2>/dev/null | grep -q '^ii ' || return 1
  [[ -f "$(supervisor_source_config)" && -f "$SUPERVISOR_CONFIG_TARGET" ]] || return 1
  cmp -s "$(supervisor_source_config)" "$SUPERVISOR_CONFIG_TARGET" || return 1
  systemctl is-active --quiet supervisor || return 1
  managed_processes_running || return 1
  ping_bench_redis
}

module_apply() {
  local source changed=0 backup="" had_existing=0 reread_status
  export DEBIAN_FRONTEND=noninteractive
  run_command "Install Supervisor" apt-get install -y --no-install-recommends supervisor
  command -v supervisord >/dev/null 2>&1 && command -v supervisorctl >/dev/null 2>&1 || fatal "Supervisor installation failed."
  run_command "Enable and start Supervisor" systemctl enable --now supervisor
  run_bench "Generate Supervisor production configuration" setup supervisor --yes
  source="$(supervisor_source_config)"
  [[ -s "$source" ]] || fatal "Bench did not generate Supervisor configuration."
  if [[ -f "$SUPERVISOR_CONFIG_TARGET" ]]; then
    backup="$(mktemp)"
    register_temp_path "$backup"
    cp -a "$SUPERVISOR_CONFIG_TARGET" "$backup"
    had_existing=1
  fi
  if atomic_install_file "$source" "$SUPERVISOR_CONFIG_TARGET" 0644 root root; then
    changed=1
  fi
  if run_command "Validate Supervisor process configuration" supervisorctl reread; then
    log_success "Supervisor configuration is valid"
  else
    reread_status=$?
    if ((had_existing)); then cp -a "$backup" "$SUPERVISOR_CONFIG_TARGET"; else rm -f -- "$SUPERVISOR_CONFIG_TARGET"; fi
    run_command "Restore Supervisor process configuration view" supervisorctl reread || true
    log_error "Supervisor rejected the generated configuration (reread exit ${reread_status}); the previous configuration was restored."
    return "$reread_status"
  fi
  if ((changed)); then
    run_command "Apply Supervisor process changes" supervisorctl update
  fi
  recover_managed_processes || fatal "No Supervisor processes matched the validated Bench prefix ${BENCH_NAME}."
  wait_for_managed_processes || fatal "One or more Frappe Supervisor processes failed to reach RUNNING state."
}

module_verify() {
  dpkg-query -W -f='${db:Status-Abbrev}' supervisor 2>/dev/null | grep -q '^ii ' || fatal "Supervisor package is not installed."
  systemctl is-active --quiet supervisor || fatal "Supervisor service is not active."
  systemctl is-enabled --quiet supervisor || fatal "Supervisor service is not enabled."
  managed_processes_running || fatal "One or more managed Frappe processes are not running."
  ping_bench_redis || fatal "One or more Bench Redis instances failed PING verification."
}

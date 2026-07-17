#!/usr/bin/env bash

supervisor_source_config() { printf '%s\n' "${BENCH_PATH}/config/supervisor.conf"; }

managed_processes_running() {
  local output managed_count bad_count
  output="$(supervisorctl status 2>/dev/null || true)"
  managed_count="$(grep -c "${BENCH_NAME}" <<<"$output" || true)"
  bad_count="$(grep "${BENCH_NAME}" <<<"$output" | grep -vc 'RUNNING' || true)"
  ((managed_count >= 5 && bad_count == 0))
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
  [[ -f "$(supervisor_source_config)" && -f "$SUPERVISOR_CONFIG_TARGET" ]] || return 1
  cmp -s "$(supervisor_source_config)" "$SUPERVISOR_CONFIG_TARGET" || return 1
  systemctl is-active --quiet supervisor || return 1
  managed_processes_running || return 1
  ping_bench_redis
}

module_apply() {
  local source changed=0 backup="" had_existing=0
  run_bench "Generate Supervisor production configuration" setup supervisor
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
  if ! supervisord -t -c /etc/supervisor/supervisord.conf >>"$LOG_FILE" 2>&1; then
    if ((had_existing)); then cp -a "$backup" "$SUPERVISOR_CONFIG_TARGET"; else rm -f -- "$SUPERVISOR_CONFIG_TARGET"; fi
    fatal "Supervisor rejected the generated configuration; the previous configuration was restored."
  fi
  log_success "Supervisor configuration is valid"
  run_command "Enable and start Supervisor" systemctl enable --now supervisor
  if ((changed)); then
    run_command "Discover Supervisor process changes" supervisorctl reread
    run_command "Apply Supervisor process changes" supervisorctl update
  fi
  wait_for_managed_processes || fatal "One or more Frappe Supervisor processes failed to reach RUNNING state."
}

module_verify() {
  systemctl is-active --quiet supervisor || fatal "Supervisor service is not active."
  systemctl is-enabled --quiet supervisor || fatal "Supervisor service is not enabled."
  managed_processes_running || fatal "One or more managed Frappe processes are not running."
  ping_bench_redis || fatal "One or more Bench Redis instances failed PING verification."
}

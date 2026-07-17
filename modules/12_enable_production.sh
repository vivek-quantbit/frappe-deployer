#!/usr/bin/env bash

production_settings_valid() {
  local config="${BENCH_PATH}/sites/common_site_config.json"
  [[ -f "$config" ]] || return 1
  jq -e '(.developer_mode // 0) == 0 and (.maintenance_mode // 0) == 0 and (.restart_supervisor_on_update // 0) == 1' "$config" >/dev/null
  jq -e '(.pause_scheduler // 0) == 0' "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json" >/dev/null
}

restart_managed_processes() {
  local process found=0
  while read -r process; do
    [[ -n "$process" ]] || continue
    found=1
    run_command "Restart Supervisor process ${process}" supervisorctl restart "$process"
  done < <(supervisorctl status | awk -v bench="$BENCH_NAME" '$1 ~ bench {print $1}')
  ((found)) || fatal "No Supervisor processes found for ${BENCH_NAME}."
}

module_description() { printf '%s\n' "Enable and harden production mode"; }

module_check() {
  production_settings_valid || return 1
  [[ "$(stat -c '%a' "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json")" == "640" ]] || return 1
  [[ "$(stat -c '%U:%G' "$BENCH_PATH")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]]
}

module_apply() {
  run_bench "Apply final site migrations" --site "$SITE_NAME" migrate
  run_bench "Clear Frappe caches" --site "$SITE_NAME" clear-cache
  run_bench "Enable production scheduler" --site "$SITE_NAME" enable-scheduler
  run_bench "Disable Frappe developer mode" set-config --global developer_mode 0 --parse
  run_bench "Disable Frappe maintenance mode" set-config --global maintenance_mode 0 --parse
  run_bench "Enable Supervisor restart integration" set-config --global restart_supervisor_on_update 1 --parse
  run_bench "Keep systemd restart integration disabled" set-config --global restart_systemd_on_update 0 --parse

  chown -R "$DEFAULT_DEPLOY_USER:$DEFAULT_DEPLOY_USER" "$BENCH_PATH"
  find "${BENCH_PATH}/sites" -type f -name '*site_config.json' -exec chmod 0640 {} +
  [[ ! -f "${BENCH_PATH}/sites/common_site_config.json" ]] || chmod 0640 "${BENCH_PATH}/sites/common_site_config.json"
  restart_managed_processes
}

module_verify() {
  production_settings_valid || fatal "Production settings were not applied correctly."
  [[ "$(stat -c '%a' "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json")" == "640" ]] || fatal "site_config.json must have mode 0640."
  [[ "$(stat -c '%U:%G' "$BENCH_PATH")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || fatal "Bench ownership is incorrect."
  supervisorctl status | awk -v bench="$BENCH_NAME" '$1 ~ bench && $2 != "RUNNING" {bad=1} END {exit bad}' || fatal "A managed process failed after production restart."
}

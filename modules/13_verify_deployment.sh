#!/usr/bin/env bash

verification_pass() { log_success "VERIFY: $1"; }

verify_service() {
  local service="${1:?service required}"
  systemctl is-active --quiet "$service" || fatal "Verification failed: ${service} is not active."
  systemctl is-enabled --quiet "$service" || fatal "Verification failed: ${service} is not enabled."
  verification_pass "${service} is active and enabled"
}

verify_supervisor_processes() {
  local output count bad
  output="$(supervisorctl status 2>/dev/null)" || fatal "Cannot query Supervisor."
  count="$(grep -c "$BENCH_NAME" <<<"$output" || true)"
  bad="$(grep "$BENCH_NAME" <<<"$output" | grep -vc RUNNING || true)"
  ((count >= 5 && bad == 0)) || fatal "Expected Frappe processes are not all RUNNING."
  verification_pass "${count} Frappe processes are RUNNING"
}

verify_redis_endpoints() {
  local config bind port response count=0
  while IFS= read -r config; do
    count=$((count + 1))
    bind="$(awk '$1 == "bind" {print $2; exit}' "$config")"
    port="$(awk '$1 == "port" {print $2; exit}' "$config")"
    [[ "$bind" == "127.0.0.1" || "$bind" == "localhost" ]] || fatal "Redis is not bound locally: ${config}"
    response="$(redis-cli --host 127.0.0.1 --port "$port" ping 2>/dev/null)"
    [[ "$response" == "PONG" ]] || fatal "Redis endpoint 127.0.0.1:${port} did not respond."
    ss -Hln "sport = :${port}" | grep -qE '127\.0\.0\.1|\[::1\]' || fatal "Redis port ${port} is not listening locally."
  done < <(find "${BENCH_PATH}/config" -maxdepth 1 -type f -name 'redis_*.conf' -print | sort)
  ((count >= 2)) || fatal "Expected Bench Redis configurations were not found."
  verification_pass "${count} local Redis endpoints responded with PONG"
}

verify_site() {
  local apps default_site scheduler_paused
  [[ -f "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json" ]] || fatal "Site configuration is missing."
  apps="$(runuser --user "$DEFAULT_DEPLOY_USER" -- env --chdir="$BENCH_PATH" "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}" "$BENCH_EXECUTABLE" --site "$SITE_NAME" list-apps 2>/dev/null | sed '/^[[:space:]]*$/d')"
  [[ "$apps" == "frappe" ]] || fatal "Expected only Frappe; found ${apps//$'\n'/, }."
  default_site="$(bench_default_site)" || fatal "Default site is missing or invalid in sites/common_site_config.json."
  [[ "$default_site" == "$SITE_NAME" ]] || fatal "Default site does not match ${SITE_NAME}."
  scheduler_paused="$(jq -r '.pause_scheduler // 0' "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json")"
  [[ "$scheduler_paused" == "0" ]] || fatal "Site scheduler is paused."
  run_bench "Verify Frappe database access" --site "$SITE_NAME" execute frappe.get_installed_apps
  verification_pass "site database, applications, and scheduler configuration"
}

verify_http() {
  local status
  nginx -t >>"$LOG_FILE" 2>&1 || fatal "Nginx configuration verification failed."
  status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --resolve "${SITE_NAME}:80:127.0.0.1" --max-time 10 "http://${SITE_NAME}/" 2>/dev/null || true)"
  [[ "$status" =~ ^(200|204|301|302|303|307|308)$ ]] || fatal "HTTP verification failed with status ${status:-unreachable}."
  verification_pass "Nginx returned HTTP ${status} for ${SITE_NAME}"
}

module_description() { printf '%s\n' "Verify complete production deployment"; }
module_check() { return 1; }
module_apply() { :; }

module_verify() {
  local service
  for service in mariadb supervisor nginx; do verify_service "$service"; done
  verify_supervisor_processes
  verify_redis_endpoints
  verify_site
  verify_http
  "${BENCH_PATH}/env/bin/python" -c 'import frappe' >/dev/null 2>&1 || fatal "Frappe import verification failed."
  verification_pass "Frappe Python environment"
}

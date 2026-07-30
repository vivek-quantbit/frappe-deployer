#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/modules/10_configure_supervisor.sh"

assert_failure "stage 10 does not use supervisord -t" grep -q 'supervisord -t' "${PROJECT_ROOT}/modules/10_configure_supervisor.sh"

exercise_supervisor_apply() {
  local root="${1:?root required}" fail_reread="${2:?failure flag required}"
  BENCH_PATH="${root}/bench"
  BENCH_NAME="production"
  SUPERVISOR_CONFIG_TARGET="${root}/frappe.conf"
  LOG_FILE="${root}/deploy.log"
  CALLS_FILE="${root}/calls"
  REREAD_COUNT_FILE="${root}/reread-count"
  mkdir -p "${BENCH_PATH}/config" "${root}/bin"
  : >"$LOG_FILE"; : >"$CALLS_FILE"; printf '0\n' >"$REREAD_COUNT_FILE"
  printf '#!/usr/bin/env bash\nprintf "production:%%s RUNNING\\n" {1..5}\n' >"${root}/bin/supervisorctl"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/bin/supervisord"
  chmod +x "${root}/bin/supervisorctl" "${root}/bin/supervisord"
  PATH="${root}/bin:${PATH}"

  run_bench() {
    printf 'generate\n' >>"$CALLS_FILE"
    printf 'new configuration\n' >"$(supervisor_source_config)"
  }
  run_command() {
    local description="$1" count
    shift
    printf '%s\n' "$description" >>"$CALLS_FILE"
    if [[ "${1-} ${2-}" == "supervisorctl reread" ]]; then
      count="$(<"$REREAD_COUNT_FILE")"; count=$((count + 1)); printf '%s\n' "$count" >"$REREAD_COUNT_FILE"
      printf 'reread output %s\n' "$count" | tee -a "$LOG_FILE"
      if [[ "$fail_reread" == 1 && "$count" == 1 ]]; then return 23; fi
    fi
  }
  register_temp_path() { :; }
  log_success() { :; }
  log_error() { printf '%s\n' "$*" >>"$LOG_FILE"; }
  wait_for_managed_processes() { return 0; }

  module_apply
}

success_root="$(mktemp -d)"
existing_failure_root="$(mktemp -d)"
new_failure_root="$(mktemp -d)"
trap 'rm -rf -- "$success_root" "$existing_failure_root" "$new_failure_root"' EXIT

assert_success "valid Supervisor configuration is applied" exercise_supervisor_apply "$success_root" 0
assert_success "Supervisor starts before reread" awk '/Enable and start Supervisor/{started=1} /Validate Supervisor process configuration/{exit !started}' "$success_root/calls"
assert_success "successful validation runs reread before update" awk '/Validate Supervisor process configuration/{reread=NR} /Apply Supervisor process changes/{exit !(reread && reread < NR)}' "$success_root/calls"
assert_success "reread output is captured in deployment log" grep -q 'reread output 1' "$success_root/deploy.log"

printf 'previous configuration\n' >"$existing_failure_root/frappe.conf"
assert_failure "failed reread rejects an existing target" exercise_supervisor_apply "$existing_failure_root" 1
assert_equal "failed reread restores an existing target" "previous configuration" "$(<"$existing_failure_root/frappe.conf")"
assert_equal "rollback performs a second reread" 2 "$(<"$existing_failure_root/reread-count")"
assert_failure "failed validation never runs update" grep -q 'Apply Supervisor process changes' "$existing_failure_root/calls"

assert_failure "failed reread rejects a new target" exercise_supervisor_apply "$new_failure_root" 1
assert_failure "failed reread removes a new target" test -e "$new_failure_root/frappe.conf"
assert_equal "new-target rollback performs a second reread" 2 "$(<"$new_failure_root/reread-count")"
assert_failure "new-target failed validation never runs update" grep -q 'Apply Supervisor process changes' "$new_failure_root/calls"

finish_tests

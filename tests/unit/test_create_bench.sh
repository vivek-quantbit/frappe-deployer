#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/logger.sh"

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
DEFAULT_DEPLOY_USER="$(id -un)"
BENCH_PARENT="$root/parent"
BENCH_NAME=production
BENCH_PATH="${BENCH_PARENT}/${BENCH_NAME}"
BENCH_VENV="$root/bench-venv"
BENCH_EXECUTABLE="${BENCH_VENV}/bin/bench"
BENCH_COMMAND_PATH="${BENCH_VENV}/bin:/usr/local/bin:/usr/bin:/bin"
FRAPPE_BRANCH=version-15
BENCH_INIT_MARKER=""
LOG_FILE="$root/test.log"; : >"$LOG_FILE"
mkdir -p "$BENCH_PARENT"
stage_is_verified() { return 1; }
fatal() { return 1; }
log_warning() { printf '%s\n' "$*" >>"$LOG_FILE"; }
run_as_deploy_user() { return 0; }
# Model the production frappe:frappe account even for CI users whose primary
# group has a different name (for example nobody:nogroup).
stat() {
  if [[ "${1:-}" == -c && "${2:-}" == '%U:%G' ]]; then
    printf '%s:%s\n' "$DEFAULT_DEPLOY_USER" "$DEFAULT_DEPLOY_USER"
  else
    command stat "$@"
  fi
}
source "${PROJECT_ROOT}/modules/06_create_bench.sh"

create_mock_bench() {
  mkdir -p "$BENCH_PATH/apps/frappe" "$BENCH_PATH/env/bin" "$BENCH_PATH/sites"
  printf '#!/bin/sh\nexit 0\n' >"$BENCH_PATH/env/bin/python"; chmod +x "$BENCH_PATH/env/bin/python"
  printf 'frappe\n' >"$BENCH_PATH/sites/apps.txt"
}

captured_command=""
run_command() { captured_command="$(printf '%q ' "$@")"; create_mock_bench; }
install() {
  local last="${*: -1}"
  if [[ "$last" == "$BENCH_PARENT" ]]; then mkdir -p "$last"; else : >"$last"; fi
}
module_apply
assert_success "successful init creates final-path virtualenv" bench_layout_valid
assert_success "bench init working directory is explicit" grep -q -- "--chdir=${BENCH_PARENT}" <<<"$captured_command"
assert_failure "successful init removes marker" test -e "${BENCH_PARENT}/.frappe-deployer-production.initializing"

rm -rf "$BENCH_PATH"; create_mock_bench; rm -rf "$BENCH_PATH/apps/frappe"
: >"${BENCH_PARENT}/.frappe-deployer-production.initializing"
BENCH_INIT_MARKER="${BENCH_PARENT}/.frappe-deployer-production.initializing"
recover_interrupted_bench
assert_success "interrupted partial bench is quarantined" sh -c 'find "$1" -maxdepth 1 -name ".production.quarantine-*" | grep -q .' _ "$BENCH_PARENT"
assert_failure "recovery removes initialization marker" test -e "$BENCH_INIT_MARKER"

mkdir -p "$BENCH_PATH/logs" "$BENCH_PATH/sites"
: >"${BENCH_PARENT}/.frappe-deployer-production.initializing"
BENCH_INIT_MARKER="${BENCH_PARENT}/.frappe-deployer-production.initializing"
recover_interrupted_bench
assert_failure "failed initialization removes partial final target" test -e "$BENCH_PATH"
assert_equal "failed and interrupted benches are separately quarantined" 2 "$(find "$BENCH_PARENT" -maxdepth 1 -name '.production.quarantine-*' | wc -l)"

mkdir -p "$BENCH_PATH"
original_definition="$(declare -f bench_contents_safe)"
bench_contents_safe() { return 1; }
assert_failure "suspicious ownership is rejected without requiring chown" quarantine_partial_bench
eval "$original_definition"
assert_success "suspicious target is preserved" test -d "$BENCH_PATH"

finish_tests

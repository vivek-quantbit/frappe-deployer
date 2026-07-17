#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/logger.sh"

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
DEFAULT_DEPLOY_USER="$(id -un)"
BENCH_PARENT="$root/parent"
BENCH_NAME="production"
BENCH_PATH="${BENCH_PARENT}/${BENCH_NAME}"
BENCH_VENV="$root/bench-venv"
BENCH_EXECUTABLE="${BENCH_VENV}/bin/bench"
BENCH_COMMAND_PATH="${BENCH_VENV}/bin:/usr/local/bin:/usr/bin:/bin"
FRAPPE_BRANCH=version-15
INSTALLER_STAGING_PATH=""
LOG_FILE="$root/test.log"; : >"$LOG_FILE"
mkdir -p "$BENCH_PARENT"
stage_is_verified() { return 1; }
fatal() { return 1; }
log_warning() { printf '%s\n' "$*" >>"$LOG_FILE"; }
run_as_deploy_user() { return 0; }
run_command() {
  local target="${*: -1}"
  mkdir -p "$target/apps/frappe" "$target/env/bin" "$target/sites"
  printf '#!/bin/sh\nexit 0\n' >"$target/env/bin/python"; chmod +x "$target/env/bin/python"
  printf 'frappe\n' >"$target/sites/apps.txt"
}
source "${PROJECT_ROOT}/modules/06_create_bench.sh"

mkdir -p "$BENCH_PATH/sites" "$BENCH_PATH/logs"
module_apply
assert_success "partial bench is quarantined" sh -c 'find "$1" -maxdepth 1 -name ".production.quarantine-*" | grep -q .' _ "$BENCH_PARENT"
assert_success "staged bench is atomically promoted" bench_layout_valid
assert_failure "staging path is absent after promotion" test -e "${BENCH_PARENT}/.frappe-deployer-production.staging"

module_check
assert_success "valid existing bench is preserved" test -d "$BENCH_PATH/apps/frappe"

rm -rf "$BENCH_PATH"; mkdir "$BENCH_PATH"
if [[ "$(id -u)" == 0 ]]; then chown 65534:65534 "$BENCH_PATH"; fi
assert_failure "suspicious ownership prevents quarantine" quarantine_partial_bench

mkdir -p "${BENCH_PARENT}/.frappe-deployer-production.staging/junk"
if [[ "$(id -u)" == 0 ]]; then chown -R "$DEFAULT_DEPLOY_USER:$DEFAULT_DEPLOY_USER" "${BENCH_PARENT}/.frappe-deployer-production.staging"; fi
assert_success "exact installer staging path is cleaned" safe_remove_staging "${BENCH_PARENT}/.frappe-deployer-production.staging"
assert_failure "cleanup refuses arbitrary paths" safe_remove_staging "$BENCH_PARENT"

finish_tests

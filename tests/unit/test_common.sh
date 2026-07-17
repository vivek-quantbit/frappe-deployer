#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/common.sh"

temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT
LOG_FILE="${temporary_dir}/test.log"
: >"$LOG_FILE"

counter_file="${temporary_dir}/counter"
printf '0\n' >"$counter_file"
assert_success "retry succeeds after transient failures" retry_command 3 0 retry-test bash -c '
  value=$(cat "$1"); value=$((value + 1)); printf "%s\n" "$value" >"$1"; ((value >= 3))
' _ "$counter_file"
assert_equal "retry attempted three times" 3 "$(<"$counter_file")"

assert_failure "retry returns failure after exhaustion" retry_command 2 0 retry-failure false

source_file="${temporary_dir}/source"
target_file="${temporary_dir}/target"
printf 'first\n' >"$source_file"
assert_success "atomic install writes changed content" atomic_install_file "$source_file" "$target_file" 0644
assert_equal "atomic install content matches" first "$(<"$target_file")"
assert_failure "atomic install reports unchanged content" atomic_install_file "$source_file" "$target_file" 0644
printf 'second\n' >"$source_file"
assert_success "atomic install replaces changed content" atomic_install_file "$source_file" "$target_file" 0644
assert_equal "atomic replacement content matches" second "$(<"$target_file")"

error_output="${temporary_dir}/error-output"
set +e
bash -Eeuo pipefail -c '
  source "$1/lib/logger.sh"
  source "$1/lib/common.sh"
  CURRENT_STAGE_NAME="Disk validation"
  register_secret "super-secret"
  install_traps
  result="$(bash -c "exit 7" super-secret)"
' _ "$PROJECT_ROOT" >"$error_output" 2>&1
error_status=$?
set -e
assert_equal "command-substitution failure preserves exit status" 7 "$error_status"
assert_equal "command-substitution failure is reported once" 1 "$(grep -c "Stage 'Disk validation' failed" "$error_output")"
assert_failure "top-level error report redacts registered secrets" grep -q super-secret "$error_output"

finish_tests

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

BENCH_VENV="${temporary_dir}/bench-venv"
BENCH_COMMAND_PATH="${BENCH_VENV}/bin:/usr/local/bin:/usr/bin:/bin"
DEFAULT_DEPLOY_USER=frappe
assert_equal "Bench PATH begins with isolated environment" "PATH=${BENCH_COMMAND_PATH}" "$(bench_environment | tail -n1)"
mkdir -p "${BENCH_VENV}/bin"
printf '#!/bin/sh\nprintf "uv-found\\n"\n' >"${BENCH_VENV}/bin/uv"; chmod +x "${BENCH_VENV}/bin/uv"
assert_equal "Bench environment resolves isolated uv" "${BENCH_VENV}/bin/uv" "$(PATH="$BENCH_COMMAND_PATH" command -v uv)"

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

stream_log="${temporary_dir}/stream.log"
stream_terminal="${temporary_dir}/stream.terminal"
LOG_FILE="$stream_log"
run_command "stream test" sh -c 'printf "visible-output\\n"' >"$stream_terminal" 2>&1
assert_success "command output is streamed to terminal" grep -q visible-output "$stream_terminal"
assert_success "command output is retained in log" grep -q visible-output "$stream_log"
assert_equal "streamed output appears once in log" 1 "$(grep -c visible-output "$stream_log")"

set +e
run_command "status test" sh -c 'exit 7' >/dev/null 2>&1
stream_status=$?
set -e
assert_equal "tee preserves command exit status" 7 "$stream_status"

secret_value="credential-do-not-print"
register_secret "$secret_value"
run_sensitive_command "sensitive heartbeat test" sh -c 'printf "%s\\n" "$1"' _ "$secret_value" >"${temporary_dir}/sensitive.terminal" 2>&1
assert_failure "sensitive command does not disclose arguments on terminal" grep -q "$secret_value" "${temporary_dir}/sensitive.terminal"
assert_failure "sensitive command output does not disclose credentials in log" grep -q "$secret_value" "$stream_log"
assert_failure "sensitive command does not log its command line" grep -q "sh -c" "$stream_log"

COMMAND_HEARTBEAT_SECONDS=1
run_command "heartbeat test" sleep 2 >"${temporary_dir}/heartbeat" 2>&1
assert_success "long command displays heartbeat" grep -q 'Still running: heartbeat test' "${temporary_dir}/heartbeat"

signal_output="${temporary_dir}/signal-output"
signal_marker="${temporary_dir}/signal-marker"
bash -c '
  source "$1/lib/logger.sh"; source "$1/lib/common.sh"
  LOG_FILE="$2"; CURRENT_STAGE_NAME=test; install_traps
  run_command "mock long process" sh -c '\''trap "printf terminated >\"$1\"; exit 0" TERM; while :; do sleep 1; done'\'' _ "$3"
' _ "$PROJECT_ROOT" "${temporary_dir}/signal.log" "$signal_marker" >"$signal_output" 2>&1 &
signal_parent=$!
sleep 0.5
kill -TERM "$signal_parent"
set +e; wait "$signal_parent"; signal_status=$?; set -e
assert_equal "TERM uses conventional exit status" 143 "$signal_status"
assert_success "TERM is forwarded to active process group" test -f "$signal_marker"
assert_equal "cancellation is reported once" 1 "$(grep -c 'Cancellation requested' "$signal_output")"

finish_tests

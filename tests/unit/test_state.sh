#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/state.sh"

fatal() { exit 1; }
temporary_state="$(mktemp -d)"
trap 'rm -rf -- "$temporary_state"' EXIT

state_init "$temporary_state"
state_set bench_name production
assert_equal "state value can be read" production "$(state_get bench_name)"
state_set bench_name production_updated
assert_equal "state update replaces old value" production_updated "$(state_get bench_name)"
assert_equal "state key remains unique" 1 "$(grep -c '^bench_name=' "$STATE_FILE")"
mark_stage_verified 07
assert_success "verified stage is detected" stage_is_verified 07
assert_failure "unverified stage is absent" stage_is_verified 08
assert_failure "invalid state key is rejected" state_set 'bad-key' value

finish_tests

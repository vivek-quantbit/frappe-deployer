#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

"${TEST_ROOT}/unit/test_validation.sh"
"${TEST_ROOT}/unit/test_logger.sh"
"${TEST_ROOT}/unit/test_common.sh"
"${TEST_ROOT}/unit/test_validate_os.sh"
"${TEST_ROOT}/unit/test_create_bench.sh"
"${TEST_ROOT}/unit/test_runtime_ordering.sh"
"${TEST_ROOT}/unit/test_configure_redis.sh"
"${TEST_ROOT}/unit/test_configure_supervisor.sh"
"${TEST_ROOT}/unit/test_state.sh"
"${TEST_ROOT}/static/test_project.sh"

if [[ "${RUN_DESTRUCTIVE_TESTS:-0}" == "1" ]]; then
  "${TEST_ROOT}/integration/test_fresh_ubuntu.sh"
fi

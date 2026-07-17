#!/usr/bin/env bash
set -Eeuo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

"${TEST_ROOT}/unit/test_validation.sh"
"${TEST_ROOT}/unit/test_logger.sh"
"${TEST_ROOT}/unit/test_common.sh"
"${TEST_ROOT}/unit/test_state.sh"
"${TEST_ROOT}/static/test_project.sh"

if [[ "${RUN_DESTRUCTIVE_TESTS:-0}" == "1" ]]; then
  "${TEST_ROOT}/integration/test_fresh_ubuntu.sh"
fi

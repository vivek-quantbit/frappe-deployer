#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/modules/01_validate_os.sh"

temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT

nested_target="${temporary_dir}/future/home/frappe/production"
resolved_path="$(existing_disk_check_path "$nested_target")"
assert_equal "disk validation uses nearest existing parent" "$temporary_dir" "$resolved_path"
if [[ ! -e "${temporary_dir}/future" ]]; then
  pass "disk path lookup does not create the future bench parent"
else
  fail "disk path lookup does not create the future bench parent"
fi
assert_success "df accepts the resolved existing parent" df -Pm "$resolved_path"

finish_tests

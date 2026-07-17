#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"

syntax_check() {
  local file
  while IFS= read -r -d '' file; do bash -n "$file" || return 1; done < <(
    find "$PROJECT_ROOT" -type f \( -name '*.sh' -o -path '*/bin/frappe-deployer' \) -print0
  )
}

module_contracts() {
  local module count=0
  while IFS= read -r module; do
    count=$((count + 1))
    unset -f module_description module_check module_apply module_verify 2>/dev/null || true
    # shellcheck source=/dev/null
    source "$module"
    declare -F module_description module_check module_apply module_verify >/dev/null || return 1
  done < <(find "${PROJECT_ROOT}/modules" -maxdepth 1 -type f -name '[0-9][0-9]_*.sh' | sort)
  ((count == 14))
}

shellcheck_all() {
  local -a files
  mapfile -d '' -t files < <(find "$PROJECT_ROOT" -type f \( -name '*.sh' -o -path '*/bin/frappe-deployer' \) -print0)
  shellcheck --severity=warning "${files[@]}"
}

cli_version_through_symlink() {
  local temporary_dir expected actual
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_dir"' RETURN
  mkdir -p "${temporary_dir}/links"
  ln -s "../link-one" "${temporary_dir}/links/frappe-deployer"
  ln -s "$PROJECT_ROOT/bin/frappe-deployer" "${temporary_dir}/link-one"
  expected="frappe-deployer $(<"${PROJECT_ROOT}/VERSION")"
  actual="$("${temporary_dir}/links/frappe-deployer" version)"
  [[ "$actual" == "$expected" ]]
}

assert_success "all Bash files pass syntax validation" syntax_check
assert_success "all fourteen modules implement the contract" module_contracts
assert_success "CLI help executes" "${PROJECT_ROOT}/bin/frappe-deployer" help
assert_success "CLI version executes" "${PROJECT_ROOT}/bin/frappe-deployer" version
assert_success "CLI version executes through chained relative and absolute symlinks" cli_version_through_symlink
assert_failure "unknown CLI command is rejected" "${PROJECT_ROOT}/bin/frappe-deployer" unknown-command

if command -v shellcheck >/dev/null 2>&1; then
  assert_success "ShellCheck passes" shellcheck_all
else
  printf 'SKIP  ShellCheck is not installed\n'
fi

finish_tests

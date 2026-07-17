#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/common.sh"

DEFAULT_DEPLOY_USER=frappe
BENCH_PATH=/safe/production
captured_runuser=""
runuser() { captured_runuser="$(printf '%q ' "$@")"; }
git_as_deploy_user branch --show-current
assert_success "Git inspection uses deployment user" grep -q -- '--user frappe' <<<"$captured_runuser"
assert_success "Git inspection uses Frappe repository as cwd" grep -q -- '--chdir=/safe/production/apps/frappe' <<<"$captured_runuser"

assert_failure "Supervisor is absent from early base packages" grep -Eq '^[[:space:]]*supervisor([[:space:]]|$)' "${PROJECT_ROOT}/lib/constants.sh"
assert_failure "stage 3 does not manage Supervisor" grep -q Supervisor "${PROJECT_ROOT}/modules/03_install_dependencies.sh"
assert_success "stage 10 installs Supervisor" grep -q 'apt-get install.*supervisor' "${PROJECT_ROOT}/modules/10_configure_supervisor.sh"

root="$(mktemp -d)"; trap 'rm -rf -- "$root"' EXIT
BENCH_PATH="$root/production"; SITE_NAME=frappe.test; TIMEZONE=UTC
mkdir -p "$BENCH_PATH/sites/$SITE_NAME"
printf 'frappe\n' >"$BENCH_PATH/sites/apps.txt"
printf '{"time_zone":"UTC"}\n' >"$BENCH_PATH/sites/$SITE_NAME/site_config.json"
printf 'frappe.test\n' >"$BENCH_PATH/sites/currentsite.txt"
bench_calls=""
run_bench() { bench_calls+="$*"$'\n'; }
run_sensitive_bench() { bench_calls+="SENSITIVE $*"$'\n'; }
fatal() { return 1; }
source "${PROJECT_ROOT}/modules/08_create_site.sh"
module_apply
assert_failure "existing site is not recreated" grep -q 'Create site' <<<"$bench_calls"
assert_failure "stage 8 does not migrate" grep -q migrate <<<"$bench_calls"
assert_failure "stage 8 does not enable scheduler" grep -q enable-scheduler <<<"$bench_calls"

finish_tests

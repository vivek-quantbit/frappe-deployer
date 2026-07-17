#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

[[ "${RUN_DESTRUCTIVE_TESTS:-0}" == "1" ]] || { printf 'Set RUN_DESTRUCTIVE_TESTS=1 on a disposable fresh VM.\n' >&2; exit 2; }
[[ "$EUID" -eq 0 ]] || { printf 'Run this integration test as root.\n' >&2; exit 2; }
[[ -n "${FRAPPE_DB_ROOT_PASSWORD:-}" && -n "${FRAPPE_ADMIN_PASSWORD:-}" ]] || {
  printf 'Set FRAPPE_DB_ROOT_PASSWORD and FRAPPE_ADMIN_PASSWORD.\n' >&2; exit 2;
}

source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 ]] || { printf 'Ubuntu 22.04 is required.\n' >&2; exit 2; }

BENCH_NAME="${TEST_BENCH_NAME:-production}"
SITE_NAME="${TEST_SITE_NAME:-frappe.test}"
TIMEZONE="${TEST_TIMEZONE:-Asia/Kolkata}"

"${PROJECT_ROOT}/scripts/install.sh"

deploy_command=(
  frappe-deployer deploy
  --bench-name "$BENCH_NAME"
  --site-name "$SITE_NAME"
  --timezone "$TIMEZONE"
)

printf 'Running first deployment...\n'
"${deploy_command[@]}"
first_state_checksum="$(sha256sum /var/lib/frappe-deployer/deployment.state | awk '{print $1}')"

printf 'Running identical deployment to test idempotency...\n'
"${deploy_command[@]}"
second_state_checksum="$(sha256sum /var/lib/frappe-deployer/deployment.state | awk '{print $1}')"
[[ "$first_state_checksum" == "$second_state_checksum" ]] || {
  printf 'Deployment state changed unexpectedly on the second run.\n' >&2; exit 1;
}

frappe-deployer verify
! grep -R -F -- "$FRAPPE_DB_ROOT_PASSWORD" /var/log/frappe-deployer /var/lib/frappe-deployer
! grep -R -F -- "$FRAPPE_ADMIN_PASSWORD" /var/log/frappe-deployer /var/lib/frappe-deployer
nginx -t
systemctl is-active --quiet mariadb supervisor nginx
systemctl is-enabled --quiet mariadb supervisor nginx

printf 'Fresh-server and idempotency integration test passed.\n'


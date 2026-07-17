#!/usr/bin/env bash

module_description() { printf '%s\n' "Print deployment summary"; }
module_check() { return 1; }
module_apply() { :; }

module_verify() {
  local frappe_version bench_version server_ip
  frappe_version="$(git_as_deploy_user describe --tags --always 2>/dev/null || printf unknown)"
  bench_version="$($BENCH_LINK --version 2>/dev/null || printf unknown)"
  server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '\nFrappe deployment completed successfully\n'
  printf '  Bench:          %s\n' "$BENCH_NAME"
  printf '  Bench path:     %s\n' "$BENCH_PATH"
  printf '  Site:           %s\n' "$SITE_NAME"
  printf '  URL:            http://%s\n' "$SITE_NAME"
  [[ -z "$server_ip" ]] || printf '  Server IP:      %s\n' "$server_ip"
  printf '  Login user:     Administrator\n'
  printf '  Login password: supplied securely during deployment\n'
  printf '  Frappe:         %s\n' "$frappe_version"
  printf '  Bench CLI:      %s\n' "$bench_version"
  printf '  Log:            %s\n' "$LOG_FILE"
  printf '\nManagement commands:\n'
  printf '  sudo frappe-deployer verify\n'
  printf '  sudo supervisorctl status\n'
  printf '  sudo -u %s -H env --chdir=%s bench --site %s migrate\n\n' "$DEFAULT_DEPLOY_USER" "$BENCH_PATH" "$SITE_NAME"
}

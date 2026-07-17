#!/usr/bin/env bash

module_description() { printf '%s\n' "Update operating system packages"; }

module_check() {
  local stamp="/var/lib/apt/periodic/update-success-stamp" now modified
  [[ -f "$stamp" ]] || return 1
  now="$(date +%s)"
  modified="$(stat -c %Y "$stamp")"
  ((now - modified < APT_MAX_AGE_SECONDS)) || return 1
  ! apt-get -s upgrade 2>/dev/null | grep -qE '^[1-9][0-9]* upgraded' || return 1
  return 0
}

module_apply() {
  export DEBIAN_FRONTEND=noninteractive
  retry_command 3 5 "Refresh APT package metadata" apt-get update -o Acquire::Retries=3
  retry_command 3 5 "Upgrade installed packages" apt-get upgrade -y -o Dpkg::Options::=--force-confold
  run_command "Repair package dependencies" apt-get install -f -y
}

module_verify() {
  dpkg --audit | grep -q . && fatal "dpkg reports incomplete package operations."
  apt-get check >>"$LOG_FILE" 2>&1 || fatal "APT dependency verification failed."
  [[ ! -f /var/run/reboot-required ]] || fatal "A reboot is required after system updates. Reboot, then rerun the same command."
}

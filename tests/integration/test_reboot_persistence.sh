#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${RUN_DESTRUCTIVE_TESTS:-0}" == "1" && "${ALLOW_TEST_REBOOT:-0}" == "1" ]] || {
  printf 'Set RUN_DESTRUCTIVE_TESTS=1 and ALLOW_TEST_REBOOT=1 on a disposable VM.\n' >&2; exit 2;
}
[[ "$EUID" -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 2; }
frappe-deployer verify

install -m 0644 /dev/stdin /etc/systemd/system/frappe-deployer-reboot-test.service <<'UNIT'
[Unit]
Description=Frappe Deployer post-reboot verification
After=network-online.target nginx.service supervisor.service mariadb.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/local/bin/frappe-deployer verify && touch /var/lib/frappe-deployer/reboot-test-passed'

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable frappe-deployer-reboot-test.service
printf 'The VM will reboot now. After reconnecting, verify /var/lib/frappe-deployer/reboot-test-passed exists.\n'
systemctl reboot


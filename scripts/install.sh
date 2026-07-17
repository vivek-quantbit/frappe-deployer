#!/usr/bin/env bash
set -Eeuo pipefail

readonly SOURCE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly INSTALL_ROOT="/opt/frappe-deployer"

[[ "$EUID" -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
install -d -m 0755 "$INSTALL_ROOT"
cp -a "${SOURCE_ROOT}/." "$INSTALL_ROOT/"
chmod 0755 "${INSTALL_ROOT}/bin/frappe-deployer"
ln -sfn "${INSTALL_ROOT}/bin/frappe-deployer" /usr/local/bin/frappe-deployer
printf 'Installed frappe-deployer to %s\n' "$INSTALL_ROOT"

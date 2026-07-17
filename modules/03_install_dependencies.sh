#!/usr/bin/env bash

all_packages_installed() {
  local package
  for package in "${BASE_PACKAGES[@]}" nodejs; do
    dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null | grep -q '^ii ' || return 1
  done
}

module_description() { printf '%s\n' "Install Frappe system dependencies"; }

module_check() {
  all_packages_installed || return 1
  command -v yarn >/dev/null 2>&1 || return 1
  command -v wkhtmltopdf >/dev/null 2>&1 || return 1
  [[ "$(node --version)" == v${NODE_MAJOR}.* ]] || return 1
  wkhtmltopdf --version 2>&1 | grep -q '0.12.6.*patched qt' || return 1
}

install_node_repository() {
  local temp_key
  temp_key="$(mktemp)"
  register_temp_path "$temp_key"
  retry_command 3 5 "Download NodeSource signing key" curl --fail --silent --show-error --location "$NODE_KEY_URL" --output "$temp_key"
  gpg --batch --yes --dearmor --output "${NODE_KEYRING}.tmp" "$temp_key"
  chmod 0644 "${NODE_KEYRING}.tmp"
  mv -f "${NODE_KEYRING}.tmp" "$NODE_KEYRING"
  printf 'deb [arch=amd64 signed-by=%s] https://deb.nodesource.com/node_%s.x nodistro main\n' "$NODE_KEYRING" "$NODE_MAJOR" >"${NODE_SOURCE_LIST}.tmp"
  chmod 0644 "${NODE_SOURCE_LIST}.tmp"
  mv -f "${NODE_SOURCE_LIST}.tmp" "$NODE_SOURCE_LIST"
}

install_wkhtmltopdf() {
  local temp_deb
  if command -v wkhtmltopdf >/dev/null 2>&1 && wkhtmltopdf --version 2>&1 | grep -q '0.12.6.*patched qt'; then
    return 0
  fi
  temp_deb="$(mktemp --suffix=.deb)"
  register_temp_path "$temp_deb"
  retry_command 3 5 "Download wkhtmltopdf ${WKHTMLTOPDF_VERSION}" curl --fail --silent --show-error --location "$WKHTMLTOPDF_URL" --output "$temp_deb"
  dpkg-deb --info "$temp_deb" >>"$LOG_FILE" 2>&1 || fatal "Downloaded wkhtmltopdf package is invalid."
  run_command "Install wkhtmltopdf with patched Qt" apt-get install -y "$temp_deb"
}

module_apply() {
  export DEBIAN_FRONTEND=noninteractive
  install_node_repository
  retry_command 3 5 "Refresh repositories after adding NodeSource" apt-get update -o Acquire::Retries=3
  run_command "Install Frappe operating-system packages" apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}" nodejs
  if ! command -v yarn >/dev/null 2>&1 || ! yarn --version 2>/dev/null | grep -q '^1\.22\.'; then
    run_command "Install Yarn 1.x using npm" npm install --global yarn@1.22.22
  fi
  install_wkhtmltopdf
  run_command "Enable MariaDB" systemctl enable --now mariadb
  run_command "Enable Redis" systemctl enable --now redis-server
  run_command "Enable Nginx" systemctl enable --now nginx
}

module_verify() {
  local command service
  all_packages_installed || fatal "One or more required system packages are missing."
  for command in python3 node npm yarn redis-server mariadb nginx wkhtmltopdf git; do
    command -v "$command" >/dev/null 2>&1 || fatal "Required executable is missing: ${command}"
  done
  [[ "$(node --version)" == v${NODE_MAJOR}.* ]] || fatal "Node.js ${NODE_MAJOR}.x is required; found $(node --version)."
  [[ "$(python3 -c 'import sys; print(sys.version_info.major, sys.version_info.minor)')" == "3 10" ]] ||
    fatal "Ubuntu 22.04 Python 3.10 is required for ${FRAPPE_BRANCH}."
  yarn --version | grep -q '^1\.22\.' || fatal "Yarn 1.22.x is required."
  wkhtmltopdf --version 2>&1 | grep -q '0.12.6.*patched qt' || fatal "wkhtmltopdf 0.12.6 with patched Qt is required."
  for service in mariadb redis-server nginx; do
    systemctl is-active --quiet "$service" || fatal "Service is not active: ${service}"
    systemctl is-enabled --quiet "$service" || fatal "Service is not enabled: ${service}"
  done
}

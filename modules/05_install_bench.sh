#!/usr/bin/env bash

deployment_user_valid() {
  id "$DEFAULT_DEPLOY_USER" >/dev/null 2>&1 || return 1
  [[ "$(getent passwd "$DEFAULT_DEPLOY_USER" | cut -d: -f6)" == "/home/${DEFAULT_DEPLOY_USER}" ]] || return 1
  [[ "$(getent passwd "$DEFAULT_DEPLOY_USER" | cut -d: -f7)" == "/bin/bash" ]] || return 1
}

module_description() { printf '%s\n' "Create deployment user and install Bench CLI"; }

module_check() {
  deployment_user_valid || return 1
  [[ -x "$BENCH_EXECUTABLE" && -x "${BENCH_VENV}/bin/uv" && -L "$BENCH_LINK" ]] || return 1
  [[ "$(readlink -f "$BENCH_LINK")" == "$BENCH_EXECUTABLE" ]] || return 1
  runuser --user "$DEFAULT_DEPLOY_USER" -- env "PATH=${BENCH_COMMAND_PATH}" \
    bash -c 'bench --version >/dev/null && uv --version >/dev/null'
}

create_deployment_user() {
  if id "$DEFAULT_DEPLOY_USER" >/dev/null 2>&1; then
    deployment_user_valid || fatal "Existing user '${DEFAULT_DEPLOY_USER}' has an incompatible home or shell."
  else
    run_command "Create dedicated ${DEFAULT_DEPLOY_USER} service account" useradd --create-home --home-dir "/home/${DEFAULT_DEPLOY_USER}" --shell /bin/bash "$DEFAULT_DEPLOY_USER"
  fi
  install -d -o "$DEFAULT_DEPLOY_USER" -g "$DEFAULT_DEPLOY_USER" -m 0750 "$BENCH_PARENT"
}

module_apply() {
  create_deployment_user
  if [[ ! -x "${BENCH_VENV}/bin/python" ]]; then
    run_command "Create isolated Bench Python environment" python3 -m venv "$BENCH_VENV"
  fi
  run_command "Upgrade Bench environment packaging tools" "${BENCH_VENV}/bin/python" -m pip install --upgrade pip setuptools wheel
  run_command "Install latest stable Bench CLI" "${BENCH_VENV}/bin/python" -m pip install --upgrade frappe-bench
  ln -sfn "$BENCH_EXECUTABLE" "$BENCH_LINK"
  chown -R root:root "$BENCH_VENV"
  chmod -R o-w "$BENCH_VENV"
}

module_verify() {
  local version
  deployment_user_valid || fatal "Deployment user validation failed."
  [[ -x "$BENCH_EXECUTABLE" ]] || fatal "Bench executable was not installed."
  [[ -x "${BENCH_VENV}/bin/uv" ]] || fatal "uv was not installed in the Bench environment."
  [[ "$(readlink -f "$BENCH_LINK")" == "$BENCH_EXECUTABLE" ]] || fatal "Global Bench link is incorrect."
  version="$(runuser --user "$DEFAULT_DEPLOY_USER" -- env "PATH=${BENCH_COMMAND_PATH}" bench --version 2>&1)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+ ]] || fatal "Bench CLI returned an invalid version: ${version}"
  runuser --user "$DEFAULT_DEPLOY_USER" -- env "PATH=${BENCH_COMMAND_PATH}" uv --version >/dev/null 2>&1 ||
    fatal "uv cannot execute as ${DEFAULT_DEPLOY_USER}."
  log_success "Bench CLI ${version} is available to ${DEFAULT_DEPLOY_USER}"
}

#!/usr/bin/env bash

bench_layout_valid_at() {
  local path="${1:?bench path required}" apps
  [[ -d "${path}/apps/frappe" && -x "${path}/env/bin/python" && -f "${path}/sites/apps.txt" ]] || return 1
  [[ "$(stat -c '%U:%G' "$path")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
  apps="$(sed '/^[[:space:]]*$/d' "${path}/sites/apps.txt")"
  [[ "$apps" == "frappe" ]] || return 1
}

bench_layout_valid() { bench_layout_valid_at "$BENCH_PATH"; }

module_description() { printf '%s\n' "Create Frappe bench"; }

bench_target_is_expected() {
  [[ "$BENCH_PATH" == "${BENCH_PARENT}/${BENCH_NAME}" && "$BENCH_PATH" != / && ! -L "$BENCH_PATH" ]]
}

module_check() {
  [[ -e "$BENCH_PATH" ]] || return 1
  if bench_layout_valid; then return 0; fi
  stage_is_verified 06 && fatal "Previously verified Bench is now invalid; operator review required: ${BENCH_PATH}"
  return 1
}

safe_remove_staging() {
  local staging="${1:?staging path required}" expected="${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.staging"
  [[ "$staging" == "$expected" && "$staging" != / && ! -L "$staging" ]] || return 1
  [[ ! -e "$staging" ]] || rm -rf --one-file-system -- "$staging"
}

quarantine_partial_bench() {
  local owner quarantine
  bench_target_is_expected || { fatal "Bench target path is suspicious; operator review required: ${BENCH_PATH}"; return 1; }
  owner="$(stat -c '%U:%G' "$BENCH_PATH")"
  [[ "$owner" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || {
    fatal "Invalid Bench target has suspicious ownership (${owner}); operator review required."
    return 1
  }
  if find -P "$BENCH_PATH" -xdev \( ! -user "$DEFAULT_DEPLOY_USER" -o -type b -o -type c -o -type p -o -type s \) -print -quit | grep -q .; then
    fatal "Invalid Bench target contains suspicious ownership or special files; operator review required."
    return 1
  fi
  quarantine="${BENCH_PARENT}/.${BENCH_NAME}.quarantine-$(date -u +%Y%m%dT%H%M%SZ)"
  [[ ! -e "$quarantine" ]] || fatal "Quarantine target already exists: ${quarantine}"
  mv -- "$BENCH_PATH" "$quarantine"
  log_warning "Moved interrupted Bench to quarantine: ${quarantine}"
}

module_apply() {
  local staging="${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.staging"
  bench_target_is_expected || fatal "Bench target does not match the validated expected path."
  if [[ -e "$BENCH_PATH" ]]; then quarantine_partial_bench; fi
  if [[ -e "$staging" ]]; then
    [[ ! -L "$staging" && "$(stat -c '%U:%G' "$staging")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] ||
      fatal "Installer staging path is suspicious; operator review required: ${staging}"
    safe_remove_staging "$staging"
  fi
  install -d -o "$DEFAULT_DEPLOY_USER" -g "$DEFAULT_DEPLOY_USER" -m 0750 "$BENCH_PARENT"
  INSTALLER_STAGING_PATH="$staging"
  # Empty stdin makes any unexpected Bench rollback prompt receive EOF.
  run_command "Initialize ${FRAPPE_BRANCH} bench" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}" \
    "$BENCH_EXECUTABLE" init --frappe-branch "$FRAPPE_BRANCH" --python /usr/bin/python3 "$staging" </dev/null
  bench_layout_valid_at "$staging" || fatal "Staged Bench did not produce the required Frappe-only layout."
  run_as_deploy_user "Verify staged Bench environment" env "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "$staging/env/bin/python" -c 'import frappe; print(frappe.__version__)'
  [[ ! -e "$BENCH_PATH" ]] || fatal "Final Bench path appeared during initialization; refusing promotion."
  mv -- "$staging" "$BENCH_PATH"
  INSTALLER_STAGING_PATH=""
}

module_verify() {
  bench_layout_valid || fatal "Bench initialization did not produce the required layout."
  run_as_deploy_user "Verify Bench environment" env "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "$BENCH_PATH/env/bin/python" -c 'import frappe; print(frappe.__version__)'
}

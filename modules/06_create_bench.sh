#!/usr/bin/env bash

bench_layout_valid() {
  [[ -d "${BENCH_PATH}/apps/frappe" ]] || return 1
  [[ -x "${BENCH_PATH}/env/bin/python" ]] || return 1
  [[ -f "${BENCH_PATH}/sites/apps.txt" ]] || return 1
  [[ "$(stat -c '%U:%G' "$BENCH_PATH")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
}

module_description() { printf '%s\n' "Create Frappe bench"; }

module_check() {
  [[ -e "$BENCH_PATH" ]] || return 1
  bench_layout_valid || fatal "Target path exists but is not a valid installer-owned bench: ${BENCH_PATH}"
}

module_apply() {
  if [[ -e "$BENCH_PATH" ]]; then
    fatal "Refusing to overwrite existing target path: ${BENCH_PATH}"
  fi
  install -d -o "$DEFAULT_DEPLOY_USER" -g "$DEFAULT_DEPLOY_USER" -m 0750 "$BENCH_PARENT"
  run_as_deploy_user "Initialize ${FRAPPE_BRANCH} bench" env \
    HOME="/home/${DEFAULT_DEPLOY_USER}" \
    PATH="/usr/local/bin:/usr/bin:/bin" \
    "$BENCH_LINK" init \
    --frappe-branch "$FRAPPE_BRANCH" \
    --python /usr/bin/python3 \
    "$BENCH_PATH"
}

module_verify() {
  local apps
  bench_layout_valid || fatal "Bench initialization did not produce the required layout."
  apps="$(sed '/^[[:space:]]*$/d' "${BENCH_PATH}/sites/apps.txt")"
  [[ "$apps" == "frappe" ]] || fatal "Unexpected applications in bench apps.txt: ${apps//$'\n'/, }"
  run_as_deploy_user "Verify Bench environment" env HOME="/home/${DEFAULT_DEPLOY_USER}" \
    "$BENCH_PATH/env/bin/python" -c 'import frappe; print(frappe.__version__)'
}


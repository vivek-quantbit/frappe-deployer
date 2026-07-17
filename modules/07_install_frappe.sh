#!/usr/bin/env bash

frappe_branch_valid() {
  [[ "$(git_as_deploy_user branch --show-current)" == "$FRAPPE_BRANCH" ]]
}

frappe_only_app() {
  local app_count app
  app_count="$(find "${BENCH_PATH}/apps" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | wc -l)"
  ((app_count == 1)) || return 1
  app="$(find "${BENCH_PATH}/apps" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')"
  [[ "$app" == "frappe" ]]
}

module_description() { printf '%s\n' "Validate Frappe Framework installation"; }

module_check() {
  [[ -d "${BENCH_PATH}/apps/frappe/.git" ]] || return 1
  frappe_branch_valid || return 1
  frappe_only_app || fatal "Phase 1 permits only the Frappe application."
  "${BENCH_PATH}/env/bin/python" -c 'import frappe' >/dev/null 2>&1 || return 1
  [[ -d "${BENCH_PATH}/sites/assets/frappe" || -L "${BENCH_PATH}/sites/assets/frappe" ]] || return 1
}

module_apply() {
  [[ -d "${BENCH_PATH}/apps/frappe/.git" ]] || fatal "Frappe repository is missing from the bench."
  frappe_branch_valid || fatal "Frappe is not on required branch ${FRAPPE_BRANCH}."
  frappe_only_app || fatal "Phase 1 permits only the Frappe application."
  run_bench "Install Frappe Python dependencies" setup requirements
  run_bench "Build Frappe frontend assets" build --app frappe
}

module_verify() {
  local remote
  frappe_branch_valid || fatal "Frappe branch validation failed."
  frappe_only_app || fatal "Unexpected application found in bench."
  remote="$(git_as_deploy_user remote get-url upstream 2>/dev/null || git_as_deploy_user remote get-url origin)"
  [[ "$remote" == *"frappe/frappe"* ]] || fatal "Unexpected Frappe Git remote: ${remote}"
  "${BENCH_PATH}/env/bin/python" -c 'import frappe' >/dev/null 2>&1 || fatal "Frappe cannot be imported in the bench environment."
  [[ -d "${BENCH_PATH}/sites/assets/frappe" || -L "${BENCH_PATH}/sites/assets/frappe" ]] || fatal "Frappe assets are missing."
}

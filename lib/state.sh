#!/usr/bin/env bash

STATE_DIR=""
STATE_FILE=""
LOCK_FILE=""
LOCK_FD=""

state_init() {
  STATE_DIR="${1:?state directory required}"
  STATE_FILE="${STATE_DIR}/deployment.state"
  LOCK_FILE="${STATE_DIR}/deployment.lock"
  install -d -m 0750 "$STATE_DIR"
  touch "$STATE_FILE" "$LOCK_FILE"
  chmod 0640 "$STATE_FILE" "$LOCK_FILE"
}

acquire_lock() {
  exec {LOCK_FD}>"$LOCK_FILE"
  flock -n "$LOCK_FD" || fatal "Another Frappe Deployer process is running."
}

state_get() {
  local key="${1:?key required}"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$STATE_FILE"
}

state_set() {
  local key="${1:?key required}" value="${2:-}" temp
  [[ "$key" =~ ^[A-Za-z0-9_]+$ ]] || fatal "Invalid state key: ${key}"
  [[ "$value" != *$'\n'* ]] || fatal "State values cannot contain line breaks."
  temp="$(mktemp "${STATE_DIR}/state.XXXXXX")"
  awk -F= -v key="$key" '$1 != key' "$STATE_FILE" >"$temp"
  printf '%s=%s\n' "$key" "$value" >>"$temp"
  chmod 0640 "$temp"
  mv -f "$temp" "$STATE_FILE"
}

stage_is_verified() { [[ "$(state_get "stage_${1}")" == "verified" ]]; }
mark_stage_verified() { state_set "stage_${1}" verified; }


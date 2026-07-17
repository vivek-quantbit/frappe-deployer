#!/usr/bin/env bash

module_description() { printf '%s\n' "Validate Ubuntu 22.04 server"; }
module_check() { return 1; }
module_apply() { :; }

module_verify() {
  local available_memory available_disk owner
  [[ -r /etc/os-release ]] || fatal "Cannot read /etc/os-release."
  # shellcheck source=/etc/os-release
  source /etc/os-release
  [[ "${ID:-}" == "$SUPPORTED_OS_ID" && "${VERSION_ID:-}" == "$SUPPORTED_OS_VERSION" ]] ||
    fatal "Only Ubuntu ${SUPPORTED_OS_VERSION} is supported; detected ${PRETTY_NAME:-unknown}."
  [[ "$(uname -m)" == "x86_64" ]] || fatal "Only x86_64 is supported in Phase 1."
  [[ "$(ps -p 1 -o comm=)" == "systemd" ]] || fatal "systemd must be PID 1."
  [[ -d /run/systemd/system ]] || fatal "The server is not running a complete systemd environment."

  available_memory="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  ((available_memory >= MIN_MEMORY_MB)) || fatal "At least ${MIN_MEMORY_MB} MB RAM is required; found ${available_memory} MB."
  available_disk="$(df -Pm "$BENCH_PARENT" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -z "$available_disk" ]]; then
    available_disk="$(df -Pm "$(dirname "$BENCH_PARENT")" 2>/dev/null | awk 'NR==2 {print $4}')"
  fi
  [[ -n "$available_disk" ]] || fatal "Cannot determine available disk space for ${BENCH_PARENT}."
  ((available_disk >= MIN_DISK_MB)) || fatal "At least ${MIN_DISK_MB} MB free disk is required; found ${available_disk} MB."

  require_command apt-get
  require_command dpkg-query
  require_command flock
  getent hosts archive.ubuntu.com >/dev/null || fatal "DNS resolution for Ubuntu repositories failed."

  if command -v ss >/dev/null 2>&1; then
    while read -r owner; do
      [[ -z "$owner" || "$owner" == *nginx* ]] || fatal "Port 80 is already owned by a conflicting process: ${owner}"
    done < <(ss -Hltpn 'sport = :80' 2>/dev/null || true)
  fi
  log_success "Ubuntu ${VERSION_ID} x86_64, ${available_memory} MB RAM, ${available_disk} MB disk available"
}


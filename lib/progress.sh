#!/usr/bin/env bash

CURRENT_STAGE=0
CURRENT_STAGE_NAME="initialization"

stage_start() {
  CURRENT_STAGE=$((CURRENT_STAGE + 1))
  CURRENT_STAGE_NAME="${1:?stage name required}"
  log_info "[$(printf '%02d' "$CURRENT_STAGE")/${TOTAL_STAGES}] ${CURRENT_STAGE_NAME}"
}

stage_success() { log_success "${CURRENT_STAGE_NAME}"; }
stage_skip() { log_info "SKIP: ${CURRENT_STAGE_NAME} (already correct)"; }


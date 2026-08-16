#!/usr/bin/env bash
# Start the Ollama Docker stack. Invoked by systemd on boot and after failures.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/opencode-3090ti}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
LOG_TAG="opencode-3090ti"
MAX_RETRIES=5
RETRY_DELAY=10

log() {
  echo "[$(date -Is)] $*"
  logger -t "${LOG_TAG}" "$*" 2>/dev/null || true
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "ERROR: must run as root"
    exit 1
  fi
}

wait_for_docker() {
  local attempt
  for attempt in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    log "waiting for docker (${attempt}/30)..."
    sleep 2
  done
  log "ERROR: docker did not become ready"
  return 1
}

validate_config() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log "ERROR: missing ${COMPOSE_FILE}"
    exit 1
  fi
}

start_stack() {
  local attempt
  for attempt in $(seq 1 "${MAX_RETRIES}"); do
    if docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans; then
      log "ollama stack started"
      return 0
    fi
    log "compose up failed (${attempt}/${MAX_RETRIES}), retrying in ${RETRY_DELAY}s..."
    sleep "${RETRY_DELAY}"
  done
  log "ERROR: failed to start stack after ${MAX_RETRIES} attempts"
  return 1
}

main() {
  require_root
  validate_config
  wait_for_docker
  start_stack
}

main "$@"

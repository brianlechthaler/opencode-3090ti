#!/usr/bin/env bash
# Pull latest repo config and Ollama container image, then apply changes.
# Default branch is main. Override to test a PR branch, e.g.:
#   sudo BRANCH=cursor/some-branch /opt/opencode-3090ti/scripts/update.sh
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/opencode-3090ti}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
BRANCH="${BRANCH:-main}"
LOG_TAG="opencode-3090ti-update"

log() {
  echo "[$(date -Is)] $*"
  logger -t "${LOG_TAG}" "$*" 2>/dev/null || true
}

image_ref() {
  awk '
    $1 == "image:" {
      print $2
      exit
    }
  ' "${COMPOSE_FILE}"
}

image_id() {
  local image
  image="$(image_ref)"
  [[ -n "${image}" ]] || return 0
  docker image inspect -f '{{.Id}}' "${image}" 2>/dev/null || echo ""
}

reload_systemd_units() {
  if [[ ! -d "${INSTALL_DIR}/systemd" ]]; then
    log "WARNING: missing ${INSTALL_DIR}/systemd; skipping unit reload"
    return 0
  fi
  install -m 644 "${INSTALL_DIR}/systemd/"*.service /etc/systemd/system/
  install -m 644 "${INSTALL_DIR}/systemd/"*.timer /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable opencode-3090ti.service opencode-3090ti-update.timer
}

sync_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log "pulling latest opencode-3090ti from ${BRANCH}"
    git -C "${INSTALL_DIR}" fetch origin "${BRANCH}"
    git -C "${INSTALL_DIR}" reset --hard "origin/${BRANCH}"
  else
    log "ERROR: ${INSTALL_DIR} is not a git checkout"
    exit 1
  fi
}

make_scripts_executable() {
  chmod +x "${INSTALL_DIR}/"*.sh 2>/dev/null || true
  chmod +x "${INSTALL_DIR}/scripts/"*.sh 2>/dev/null || true
}

apply_container_update() {
  local before after image
  image="$(image_ref)"
  before="$(image_id)"
  log "pulling ${image}"
  docker compose -f "${COMPOSE_FILE}" pull
  after="$(image_id)"

  if [[ "${before}" != "${after}" || "${before}" == "" ]]; then
    log "image updated; recreating container"
  else
    log "image unchanged; ensuring stack is up"
  fi
  docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    log "docker unavailable; skipping update"
    exit 0
  fi

  sync_repo
  make_scripts_executable
  reload_systemd_units
  apply_container_update
  log "update complete"
}

main "$@"

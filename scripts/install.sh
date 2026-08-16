#!/usr/bin/env bash
# One-time installer: clone repo, configure systemd, and start the Ollama stack.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/opencode-3090ti}"
REPO_URL="${REPO_URL:-https://github.com/brianlechthaler/opencode-3090ti.git}"
BRANCH="${BRANCH:-main}"
LOG_TAG="opencode-3090ti-install"

log() {
  echo "[$(date -Is)] $*"
  logger -t "${LOG_TAG}" "$*" 2>/dev/null || true
}

require_root() {
  if [[ "${EUID}" -ne 0 && "${ALLOW_NONROOT:-0}" != "1" ]]; then
    echo "Run as root: sudo $0"
    exit 1
  fi
}

install_packages() {
  if ! command -v git >/dev/null; then
    apt-get update -qq
    apt-get install -y git
  fi
}

clone_or_update_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log "updating existing install at ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" fetch origin "${BRANCH}"
    git -C "${INSTALL_DIR}" reset --hard "origin/${BRANCH}"
  else
    log "cloning ${REPO_URL} to ${INSTALL_DIR}"
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
  fi
}

make_scripts_executable() {
  chmod +x "${INSTALL_DIR}/"*.sh
  chmod +x "${INSTALL_DIR}/scripts/"*.sh
}

install_systemd_units() {
  if [[ "${SKIP_SYSTEMD:-0}" == "1" ]]; then
    log "SKIP_SYSTEMD=1; skipping systemd unit install"
    return 0
  fi
  install -m 644 "${INSTALL_DIR}/systemd/"*.service /etc/systemd/system/
  install -m 644 "${INSTALL_DIR}/systemd/"*.timer /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable opencode-3090ti.service
  systemctl enable opencode-3090ti-update.timer
}

start_services() {
  if [[ "${SKIP_START:-0}" == "1" ]]; then
    log "SKIP_START=1; skipping service start"
    return 0
  fi
  systemctl start opencode-3090ti-update.timer
  systemctl restart opencode-3090ti.service
  log "opencode-3090ti started"
}

main() {
  require_root
  install_packages
  clone_or_update_repo
  make_scripts_executable
  install_systemd_units
  start_services

  if [[ "${SKIP_START:-0}" == "1" ]]; then
    log "install complete (services not started)"
    return 0
  fi

  cat <<EOF

Install complete.

Ollama stack:
  systemctl status opencode-3090ti
  docker logs -f ollama

Auto-updates every 6 hours:
  systemctl list-timers 'opencode-3090ti-*'
  sudo ${INSTALL_DIR}/scripts/update.sh

Optional model / OpenCode setup (as your normal user):
  cd ${INSTALL_DIR}
  ./setup-model.sh
  ./setup-opencode.sh

EOF
}

main "$@"

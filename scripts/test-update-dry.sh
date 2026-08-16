#!/usr/bin/env bash
# Dry-run the host updater against a temporary git checkout (no systemd).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
INSTALL_DIR="${TMP_DIR}/opt/opencode-3090ti"
BRANCH_NAME="test-update-branch-$$"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "== seed temporary install checkout =="
mkdir -p "$(dirname "${INSTALL_DIR}")"
git clone --local --no-hardlinks "${ROOT}" "${INSTALL_DIR}" >/dev/null 2>&1 \
  || fail "failed to clone repo into ${INSTALL_DIR}"
# Ensure the clone has an origin remote that fetch can use.
git -C "${INSTALL_DIR}" checkout -B "${BRANCH_NAME}" >/dev/null 2>&1
git -C "${ROOT}" branch "${BRANCH_NAME}" >/dev/null 2>&1 || true
# Point origin at the real workspace so fetch/reset works offline.
git -C "${INSTALL_DIR}" remote set-url origin "${ROOT}"
git -C "${ROOT}" update-ref "refs/heads/${BRANCH_NAME}" HEAD
pass "temporary install dir ready at ${INSTALL_DIR}"

echo
echo "== image_ref extraction =="
# shellcheck disable=SC1091
image="$(
  INSTALL_DIR="${INSTALL_DIR}" bash -c '
    COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
    awk '\''$1 == "image:" { print $2; exit }'\'' "${COMPOSE_FILE}"
  '
)"
[[ "${image}" == ollama/ollama:* ]] || fail "unexpected image ref: ${image}"
pass "image_ref=${image}"

echo
echo "== update.sh sync (skip systemd + compose) =="
# Mutate a tracked file, then prove update.sh resets it from origin/BRANCH.
# Run the working-tree updater (not the clone's possibly stale copy).
echo "stale-marker" >> "${INSTALL_DIR}/README.md"
env ALLOW_NONROOT=1 SKIP_SYSTEMD=1 SKIP_COMPOSE=1 \
  INSTALL_DIR="${INSTALL_DIR}" BRANCH="${BRANCH_NAME}" \
  bash "${ROOT}/scripts/update.sh" || fail "update.sh dry-run failed"

if grep -q 'stale-marker' "${INSTALL_DIR}/README.md"; then
  fail "update.sh did not reset working tree to origin/${BRANCH_NAME}"
fi
pass "update.sh git sync restored checkout"

echo
echo "== scripts stay executable after update =="
for script in install.sh update.sh start.sh ollama-version.sh; do
  [[ -x "${INSTALL_DIR}/scripts/${script}" ]] || fail "${script} is not executable after update"
done
pass "scripts remain executable"

echo
echo "== non-root guard =="
if env INSTALL_DIR="${INSTALL_DIR}" bash "${ROOT}/scripts/update.sh" >/dev/null 2>&1; then
  fail "update.sh should refuse non-root without ALLOW_NONROOT=1"
fi
pass "update.sh requires root by default"

echo
echo "== install.sh root guard =="
if bash "${ROOT}/scripts/install.sh" >/dev/null 2>&1; then
  fail "install.sh should refuse non-root"
fi
pass "install.sh requires root"

echo
echo "Update dry-run tests passed"

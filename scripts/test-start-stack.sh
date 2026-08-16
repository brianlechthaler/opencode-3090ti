#!/usr/bin/env bash
# Exercise scripts/start.sh (systemd entrypoint) without touching host units.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

echo "== root guard =="
if INSTALL_DIR="${tmpdir}/missing" bash ./scripts/start.sh >/tmp/start-root.out 2>&1; then
  fail "start.sh should require root without ALLOW_NONROOT=1"
fi
grep -qi 'must run as root' /tmp/start-root.out || fail "start.sh root error message"
pass "start.sh requires root"

echo
echo "== missing compose file =="
if ALLOW_NONROOT=1 INSTALL_DIR="${tmpdir}/empty" bash ./scripts/start.sh >/tmp/start-missing.out 2>&1; then
  fail "start.sh should fail when compose file is missing"
fi
grep -qi 'missing' /tmp/start-missing.out || fail "start.sh missing-compose message"
pass "start.sh validates compose path"

echo
echo "== starts stack with CI overlay via compose file =="
install_dir="${tmpdir}/opt/opencode-3090ti"
mkdir -p "${install_dir}"
# Use CI overlay so GPU-less environments can start.
cat > "${install_dir}/docker-compose.yml" <<EOF
services:
  ollama:
    image: ollama/ollama:$(bash scripts/ollama-version.sh current)
    container_name: start-stack-test-$$
    ports:
      - "127.0.0.1:0:11434"
    volumes:
      - ollama_data:/root/.ollama
volumes:
  ollama_data:
EOF

if ! docker info >/dev/null 2>&1 && ! sudo docker info >/dev/null 2>&1; then
  fail "docker required for start-stack test"
fi

# scripts/start.sh calls `docker compose` (not sudo). Ensure docker works for current user.
if ! docker info >/dev/null 2>&1; then
  sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
fi

ALLOW_NONROOT=1 INSTALL_DIR="${install_dir}" bash ./scripts/start.sh \
  >/tmp/start-ok.out 2>&1 || {
  cat /tmp/start-ok.out >&2
  fail "start.sh failed to start stack"
}
grep -qi 'ollama stack started' /tmp/start-ok.out || fail "start.sh success log missing"
pass "start.sh brings stack up"

# Cleanup container created with fixed container_name.
docker rm -f "start-stack-test-$$" >/dev/null 2>&1 || true
# Also remove anonymous project resources if compose named them from directory.
docker compose -f "${install_dir}/docker-compose.yml" down -v >/dev/null 2>&1 || true

echo
echo "== systemd unit points at start.sh =="
grep -q 'ExecStart=/opt/opencode-3090ti/scripts/start.sh' systemd/opencode-3090ti.service \
  || fail "systemd service ExecStart mismatch"
pass "systemd service wiring"

echo
echo "Start-stack tests passed"

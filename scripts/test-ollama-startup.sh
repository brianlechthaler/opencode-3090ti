#!/usr/bin/env bash
# Pull and start the pinned Ollama image (CPU/CI overlay) and hit the HTTP API.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

PROJECT="opencode-ollama-test-$$"
WAIT_SECONDS="${WAIT_SECONDS:-90}"
OVERRIDE="$(mktemp)"
DOCKER=(docker)

if ! docker info >/dev/null 2>&1; then
  if sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "FAIL: docker is not available" >&2
    exit 1
  fi
fi

COMPOSE=("${DOCKER[@]}" compose -p "${PROJECT}" -f docker-compose.yml -f docker-compose.ci.yml -f "${OVERRIDE}")

fail() {
  echo "FAIL: $*" >&2
  "${COMPOSE[@]}" logs ollama >&2 || true
  exit 1
}

pass() {
  echo "PASS: $*"
}

cleanup() {
  "${COMPOSE[@]}" down -v >/dev/null 2>&1 || true
  rm -f "${OVERRIDE}"
}
trap cleanup EXIT

cat > "${OVERRIDE}" <<EOF
services:
  ollama:
    container_name: ${PROJECT}-ollama
    ports: !override
      - "127.0.0.1:0:11434"
EOF

echo "== pinned image =="
pinned="$(bash scripts/ollama-version.sh current)"
image="ollama/ollama:${pinned}"
pass "using ${image}"

echo
echo "== compose config (CI overlay) =="
"${COMPOSE[@]}" config --quiet || fail "compose config failed with CI overlay"
rendered="$("${COMPOSE[@]}" config)"
if grep -qE 'device_ids:|driver: nvidia|count: all' <<<"${rendered}"; then
  echo "${rendered}" >&2
  fail "CI overlay still requests NVIDIA devices"
fi
pass "CI overlay clears GPU requirements"

echo
echo "== pull image =="
"${COMPOSE[@]}" pull || fail "docker compose pull failed"
pass "pulled ${image}"

echo
echo "== start stack =="
"${COMPOSE[@]}" up -d --remove-orphans || fail "docker compose up failed"
pass "compose up succeeded"

cid="$("${COMPOSE[@]}" ps -q ollama)"
[[ -n "${cid}" ]] || fail "ollama container id not found"

echo
echo "== wait for API =="
host_port="$("${DOCKER[@]}" port "${cid}" 11434/tcp 2>/dev/null | head -1 | sed -E 's/.*://')"
[[ -n "${host_port}" ]] || fail "could not resolve published port for 11434"
api="http://127.0.0.1:${host_port}/api/tags"
pass "API endpoint ${api}"

deadline=$((SECONDS + WAIT_SECONDS))
state=""
while (( SECONDS < deadline )); do
  state="$("${DOCKER[@]}" inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo missing)"
  if [[ "${state}" == "exited" ]]; then
    fail "container exited during startup (state=${state})"
  fi
  if [[ "${state}" == "running" ]] && curl -fsS "${api}" >/tmp/ollama-tags.json 2>/dev/null; then
    break
  fi
  sleep 2
done

[[ "${state}" == "running" ]] || fail "container did not stay running (state=${state})"
curl -fsS "${api}" >/tmp/ollama-tags.json || fail "Ollama /api/tags did not become ready within ${WAIT_SECONDS}s"
python3 -m json.tool /tmp/ollama-tags.json >/dev/null || fail "/api/tags returned invalid JSON"
pass "Ollama API is healthy"

echo
echo "== version inside container =="
version_out="$("${DOCKER[@]}" exec "${cid}" ollama --version 2>&1 || true)"
[[ -n "${version_out}" ]] || fail "ollama --version produced no output"
pass "ollama --version: ${version_out}"

logs="$("${DOCKER[@]}" logs "${cid}" 2>&1 || true)"
if grep -qiE 'panic:|fatal error|exec format error' <<<"${logs}"; then
  echo "${logs}" >&2
  fail "container logs contain fatal startup errors"
fi
pass "container logs show no fatal startup errors"

echo
echo "Ollama startup test passed"

#!/usr/bin/env bash
# Exercise scripts/ollama-version.sh against the repo pin and GitHub releases API.
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

echo "== usage guard =="
if bash scripts/ollama-version.sh >/dev/null 2>&1; then
  fail "ollama-version.sh with no args should fail"
fi
pass "missing args exits non-zero"

echo
echo "== current =="
current="$(bash scripts/ollama-version.sh current)"
[[ "${current}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "current is not semver: ${current}"
compose_pin="$(grep -oE 'ollama/ollama:[0-9]+\.[0-9]+\.[0-9]+' docker-compose.yml | head -1 | sed 's/.*://')"
[[ "${current}" == "${compose_pin}" ]] || fail "current (${current}) != compose (${compose_pin})"
pass "current=${current}"

echo
echo "== latest =="
latest="$(bash scripts/ollama-version.sh latest)"
[[ "${latest}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "latest is not semver: ${latest}"
pass "latest=${latest}"

echo
echo "== ordering sanity =="
# latest should be >= current when sorted as versions (equal is fine).
newer="$(printf '%s\n%s\n' "${current}" "${latest}" | sort -V | tail -1)"
[[ "${newer}" == "${latest}" ]] || fail "latest (${latest}) is older than current (${current})"
pass "latest is greater than or equal to current"

echo
echo "== bump dry-run (no write) =="
# Confirm the sed replacement the bump workflow uses would be a no-op or a clean swap.
tmp="$(mktemp)"
cp docker-compose.yml "${tmp}"
sed -i "s|ollama/ollama:${current}|ollama/ollama:${latest}|g" "${tmp}"
grep -q "image: ollama/ollama:${latest}" "${tmp}" || fail "bump sed did not produce expected image line"
rm -f "${tmp}"
pass "version-bump sed pattern works (${current} -> ${latest})"

echo
echo "Ollama version tests passed"

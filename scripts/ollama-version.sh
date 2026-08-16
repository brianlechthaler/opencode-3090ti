#!/usr/bin/env bash
# Print the Ollama Docker image version pinned in docker-compose.yml, or the
# latest stable release published on GitHub (maps to ollama/ollama Docker tags).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT}/docker-compose.yml"

current_version() {
  grep -oE 'ollama/ollama:[0-9]+\.[0-9]+\.[0-9]+' "${COMPOSE_FILE}" \
    | head -1 \
    | sed 's/.*://'
}

latest_version() {
  local tag
  # releases/latest skips prereleases; strip leading "v" to match Docker Hub tags.
  tag="$(curl -sf "https://api.github.com/repos/ollama/ollama/releases/latest" \
    | jq -r '.tag_name // empty')"

  if [[ -z "${tag}" ]]; then
    echo "error: could not resolve latest Ollama release from GitHub" >&2
    exit 1
  fi

  tag="${tag#v}"
  if [[ ! "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: unexpected Ollama release tag '${tag}'" >&2
    exit 1
  fi

  printf '%s\n' "${tag}"
}

case "${1:-}" in
  current) current_version ;;
  latest) latest_version ;;
  *)
    echo "usage: $0 {current|latest}" >&2
    exit 1
    ;;
esac

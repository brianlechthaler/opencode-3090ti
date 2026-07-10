#!/usr/bin/env bash
# Interactive OpenCode launcher with long bash timeouts for docker builds.
set -euo pipefail

cd "$(dirname "$0")"
export PATH="${HOME}/.opencode/bin:${PATH}"
export OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS="${OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS:-600000}"

if ! command -v opencode &>/dev/null; then
  echo "OpenCode not installed. Run: ./setup-opencode.sh"
  exit 1
fi

exec opencode "$@"

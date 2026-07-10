#!/usr/bin/env bash
# Run OpenCode non-interactively. opencode run needs a TTY for skill init;
# without one it hangs ~60s and exits without running the agent loop.
set -euo pipefail

cd "$(dirname "$0")"
export PATH="${HOME}/.opencode/bin:${PATH}"
# Bash tool defaults to 2m; docker builds need up to 10m.
export OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS="${OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS:-600000}"

if ! command -v opencode &>/dev/null; then
  echo "OpenCode not installed. Run: ./setup-opencode.sh"
  exit 1
fi

if ! curl -fsS "${OLLAMA_URL:-http://localhost:11434}/api/tags" &>/dev/null; then
  echo "Ollama is not running. Start it first: ./start.sh"
  exit 1
fi

ARGS=(run --auto)
if [[ -t 1 ]]; then
  exec opencode "${ARGS[@]}" "$@"
fi

if command -v script &>/dev/null; then
  exec script -q -c "opencode $(printf '%q ' "${ARGS[@]}" "$@")" /dev/null
fi

echo "warning: no TTY and 'script' not found; opencode run may hang" >&2
exec opencode "${ARGS[@]}" "$@"

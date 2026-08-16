#!/usr/bin/env bash
# Run the full local/CI test suite for this repository.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "############################################"
echo "# opencode-3090ti test suite"
echo "############################################"
echo

bash scripts/test-static.sh
echo
bash scripts/test-ollama-version.sh
echo
bash scripts/test-update-dry.sh
echo

if [[ "${SKIP_STARTUP:-0}" == "1" ]]; then
  echo "SKIP_STARTUP=1; skipping Ollama Docker startup test"
else
  bash scripts/test-ollama-startup.sh
fi

echo
echo "############################################"
echo "# All tests passed"
echo "############################################"

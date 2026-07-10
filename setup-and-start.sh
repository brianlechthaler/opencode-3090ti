#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if docker info &>/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif sudo docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
else
  echo "Docker is not accessible. Either:"
  echo "  1. Run: sudo usermod -aG docker \"\$USER\"  (then log out and back in)"
  echo "  2. Or run this script in a terminal so sudo can prompt for your password"
  exit 1
fi

if ! "${COMPOSE[@]}" version &>/dev/null 2>&1; then
  echo "Docker daemon is not running. Start it with: sudo systemctl start docker"
  exit 1
fi

"${COMPOSE[@]}" up -d

echo ""
echo "Ollama is running on GPU at http://localhost:11434"
echo ""
echo "Pull the coding model (first time, ~18 GB download):"
echo "  ./setup-model.sh"
echo ""
echo "Wire up OpenCode:"
echo "  ./setup-opencode.sh"
echo ""
echo "Run a task (non-interactive):"
echo "  ./run-opencode.sh \"your task here\""
echo ""
echo "Interactive TUI:"
echo "  ./opencode.sh"
echo ""
echo "Test:"
echo "  curl http://localhost:11434/api/tags"

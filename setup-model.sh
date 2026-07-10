#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

BASE_MODEL="${OLLAMA_MODEL:-qwen3-coder:30b}"
CUSTOM_MODEL="${OLLAMA_CUSTOM_MODEL:-qwen3-coder-30b-opencode}"
MODelfile="${OLLAMA_MODELFILE:-Modelfile.qwen3-coder}"
PULL_TIMEOUT="${PULL_TIMEOUT:-300}"

if docker info &>/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif sudo docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
else
  echo "Docker is not accessible."
  exit 1
fi

if ! curl -fsS http://localhost:11434/api/tags &>/dev/null; then
  echo "Ollama is not running. Start it first: ./start.sh"
  exit 1
fi

if ! "${COMPOSE[@]}" exec -T ollama ollama list 2>/dev/null | grep -q "^llama3.2-opencode:latest[[:space:]]"; then
  echo "Creating llama3.2-opencode (interim — native tool calling, no download)..."
  docker cp Modelfile.llama ollama:/tmp/Modelfile.opencode
  "${COMPOSE[@]}" exec -T ollama ollama create llama3.2-opencode:latest -f /tmp/Modelfile.opencode
fi

if "${COMPOSE[@]}" exec -T ollama ollama list 2>/dev/null | grep -q "^${BASE_MODEL}[[:space:]]"; then
  echo "${BASE_MODEL} already installed."
else
  echo "Pulling ${BASE_MODEL}..."
  attempt=0
  while ! "${COMPOSE[@]}" exec -T ollama ollama list 2>/dev/null | grep -q "^${BASE_MODEL}[[:space:]]"; do
    attempt=$((attempt + 1))
    echo "--- pull attempt ${attempt} ---"
    docker exec ollama pkill -f "ollama pull" 2>/dev/null || true
    sleep 2
    if timeout "${PULL_TIMEOUT}" "${COMPOSE[@]}" exec -T ollama ollama pull "$BASE_MODEL"; then
      break
    fi
    echo "Pull timed out or stalled; resuming from saved chunks..."
    sleep 3
  done
fi

echo "Creating ${CUSTOM_MODEL}..."
docker cp "$MODelfile" ollama:/tmp/Modelfile.opencode
"${COMPOSE[@]}" exec -T ollama ollama create "${CUSTOM_MODEL}:latest" -f /tmp/Modelfile.opencode

echo ""
echo "Model ready: ${CUSTOM_MODEL}:latest"
echo "Context window: 64k tokens (num_ctx 65536)"
echo ""
echo "If you changed context length, restart Ollama and recreate the model:"
echo "  docker compose up -d --force-recreate ollama"
echo "  ./setup-model.sh"
echo ""
echo "Update OpenCode: OPENCODE_MODEL=${CUSTOM_MODEL}:latest ./setup-opencode.sh"

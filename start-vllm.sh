#!/usr/bin/env bash
# Start vLLM (stops Ollama first to free GPU).
set -euo pipefail

cd "$(dirname "$0")"

if docker info &>/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif sudo docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
else
  echo "Docker is not accessible."
  exit 1
fi

VOLUME="$("${COMPOSE[@]}" -f docker-compose.vllm.yml config --format json | python3 -c "
import json, sys
print(json.load(sys.stdin)['volumes']['huggingface_cache']['name'])
")"
CACHE_SIZE=$(docker run --rm -v "${VOLUME}:/cache" alpine du -sm /cache 2>/dev/null | cut -f1)
if [[ "${CACHE_SIZE:-0}" -lt 10000 ]]; then
  echo "Model not fully downloaded (${CACHE_SIZE:-0} MB in cache, need ~31000 MB)."
  echo "Run: ./pull-model-vllm.sh"
  exit 1
fi

echo "Stopping Ollama to free GPU..."
"${COMPOSE[@]}" stop ollama 2>/dev/null || true

echo "Starting vLLM..."
"${COMPOSE[@]}" -f docker-compose.vllm.yml up -d

echo ""
echo "vLLM starting on http://localhost:8000"
echo "Watch logs: docker compose -f docker-compose.vllm.yml logs -f vllm"
echo "Test:       curl http://localhost:8000/v1/models"

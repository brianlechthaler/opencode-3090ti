#!/usr/bin/env bash
# Pre-download the vLLM model to the HuggingFace cache volume before starting vLLM.
set -euo pipefail

cd "$(dirname "$0")"

MODEL="${VLLM_MODEL:-Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"

if docker info &>/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif sudo docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
else
  echo "Docker is not accessible."
  exit 1
fi

echo "Model: ${MODEL}"
echo "Expected download: ~31 GB (4 safetensors shards)"
echo ""

# Ensure the cache volume exists
"${COMPOSE[@]}" -f docker-compose.vllm.yml create vllm 2>/dev/null || true

VOLUME="$("${COMPOSE[@]}" -f docker-compose.vllm.yml config --format json | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
vol = cfg['volumes']['huggingface_cache']['name']
print(vol)
")"

echo "Cache volume: ${VOLUME}"
echo ""

# Show current cache size
BEFORE=$(docker run --rm -v "${VOLUME}:/cache" alpine du -sh /cache 2>/dev/null | cut -f1)
echo "Cache before download: ${BEFORE}"
echo ""

ENV_ARGS=()
if [[ -n "$HF_TOKEN" ]]; then
  ENV_ARGS=(-e "HF_TOKEN=${HF_TOKEN}" -e "HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}")
  echo "Using HF_TOKEN for authenticated download (higher rate limits)."
else
  echo "No HF_TOKEN set — download may be rate-limited. Set HF_TOKEN for faster pulls."
fi
echo ""

echo "Starting download (progress below)..."
docker run --rm \
  --entrypoint python3 \
  -v "${VOLUME}:/root/.cache/huggingface" \
  "${ENV_ARGS[@]}" \
  vllm/vllm-openai:latest \
  -c "
from huggingface_hub import snapshot_download
import sys
model = sys.argv[1]
print(f'Downloading {model}...')
path = snapshot_download(repo_id=model, resume_download=True)
print(f'Done: {path}')
" "$MODEL"

AFTER=$(docker run --rm -v "${VOLUME}:/cache" alpine du -sh /cache 2>/dev/null | cut -f1)
echo ""
echo "Cache after download: ${AFTER}"
echo "Model ready. Start vLLM with: ./start-vllm.sh"

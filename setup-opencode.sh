#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.json"
# qwen3-coder-30b-opencode: native tool_calls via RENDERER/PARSER qwen3-coder
# (qwen2.5-coder emits tool JSON in content — OpenCode can't execute those)
MODEL_ID="${OPENCODE_MODEL:-qwen3-coder-30b-opencode:latest}"

if ! command -v opencode &>/dev/null; then
  echo "Installing OpenCode..."
  curl -fsSL https://opencode.ai/install | bash
  export PATH="${HOME}/.opencode/bin:${PATH}"
fi

if ! curl -fsS "${OLLAMA_URL}/api/tags" &>/dev/null; then
  echo "Ollama is not reachable at ${OLLAMA_URL}."
  echo "Start it first: ./start.sh"
  exit 1
fi

if ! curl -fsS "${OLLAMA_URL}/api/tags" | python3 -c "import json,sys; models=[m['name'] for m in json.load(sys.stdin).get('models',[])]; target='${MODEL_ID}'; sys.exit(0 if target in models or target.split(':')[0]+':latest' in models else 1)" 2>/dev/null; then
  echo "Model ${MODEL_ID} not found. Run: ./setup-model.sh"
  exit 1
fi

mkdir -p "$(dirname "$OPENCODE_CONFIG")"
cp opencode.json "$OPENCODE_CONFIG"
# Keep user config model in sync with OPENCODE_MODEL
python3 - "$OPENCODE_CONFIG" "$MODEL_ID" <<'PY'
import json, sys
path, model_id = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["model"] = f"ollama/{model_id}"
models = cfg.get("provider", {}).get("ollama", {}).get("models", {})
if model_id not in models:
    models[model_id] = {
        "name": model_id,
        "tools": True,
        "limit": {"context": 65536, "output": 16384},
    }
cfg.setdefault("provider", {}).setdefault("ollama", {})["options"] = {
    "baseURL": __import__("os").environ.get("OLLAMA_URL", "http://localhost:11434") + "/v1",
    "timeout": 600000,
    "chunkTimeout": 120000,
}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

echo "OpenCode configured at ${OPENCODE_CONFIG}"
echo "Default model: ollama/${MODEL_ID}"
echo "Bash default timeout: 10 minutes (via OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS)"
echo ""
echo "Interactive TUI (from a project directory, not ~):"
echo "  cd ~/Projects/ollama-docker && ./opencode.sh"
echo ""
echo "Non-interactive (scripts/CI — allocates a TTY automatically):"
echo "  ./run-opencode.sh \"your task here\""

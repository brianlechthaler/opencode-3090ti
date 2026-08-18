# Model setup

Pulls base Ollama weights and creates custom models with OpenCode-friendly system prompts and tool-calling settings.

## Overview

`setup-model.sh`:

1. Creates `llama3.2-opencode` from `Modelfile.llama` (no large download; interim fallback)
2. Pulls the base model (default `qwen3.8:latest`, ~17 GB) with retry on timeout
3. Runs `ollama create` with the chosen Modelfile to produce a tagged custom model

Default output: `qwen3.8-opencode:latest` with 64k context.

## Usage

```bash
./setup-model.sh
```

### Alternative models

**Qwen3 Coder 30B** (previous default):

```bash
OLLAMA_MODEL=qwen3-coder:30b \
OLLAMA_CUSTOM_MODEL=qwen3-coder-30b-opencode \
OLLAMA_MODELFILE=Modelfile.qwen3-coder \
./setup-model.sh
```

**Qwen3 8B** (less VRAM):

```bash
OLLAMA_MODEL=qwen3:8b \
OLLAMA_CUSTOM_MODEL=qwen3-8b-opencode \
OLLAMA_MODELFILE=Modelfile.qwen3 \
./setup-model.sh
```

**Qwen2.5 Coder 14B** (not recommended for OpenCode — no native tool calls):

```bash
OLLAMA_MODEL=qwen2.5-coder:14b \
OLLAMA_CUSTOM_MODEL=qwen2.5-coder-14b-opencode \
OLLAMA_MODELFILE=Modelfile.qwen2.5-coder-14b \
./setup-model.sh
```

After switching models, update OpenCode:

```bash
OPENCODE_MODEL=qwen3-coder-30b-opencode:latest ./setup-opencode.sh
```

## Modelfile contents

All OpenCode-oriented Modelfiles set:

- `num_ctx 65536` — 64k context window
- `num_gpu 999` — full GPU offload
- `temperature 0.2`

`Modelfile.qwen3-coder` adds:

```
RENDERER qwen3-coder
PARSER qwen3-coder
```

These enable native `tool_calls` in the API response. Without them, the model may emit tool JSON as plain text, which OpenCode cannot execute.

The system prompt instructs the agent to use absolute paths, native tool calls, and 10-minute bash timeouts.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `OLLAMA_MODEL` | `qwen3.8:latest` | Base model to pull |
| `OLLAMA_CUSTOM_MODEL` | `qwen3.8-opencode` | Name for `ollama create` |
| `OLLAMA_MODELFILE` | `Modelfile.qwen3.8` | Modelfile path |
| `PULL_TIMEOUT` | `300` | Seconds per pull attempt |

## After changing context length

Restart Ollama and recreate the model:

```bash
docker compose up -d --force-recreate ollama
./setup-model.sh
```

## Troubleshooting

**Pull keeps timing out** — re-run `./setup-model.sh`. Partial chunks are preserved (`OLLAMA_NOPRUNE=1`).

**Model list empty** — confirm Ollama is running: `curl http://localhost:11434/api/tags`.

## Related

- [OpenCode configuration](opencode-config.md)
- [Architecture](../architecture.md)

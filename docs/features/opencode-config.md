# OpenCode configuration

Installs the OpenCode CLI and copies `opencode.json` to `~/.config/opencode/opencode.json`.

## Overview

`setup-opencode.sh`:

1. Installs OpenCode via `https://opencode.ai/install` if missing
2. Verifies Ollama is reachable and the target model exists
3. Copies `opencode.json` and patches the active model ID and Ollama base URL

Default model: `ollama/qwen3-coder-30b-opencode:latest`.

## Usage

```bash
./setup-opencode.sh
```

Switch models:

```bash
OPENCODE_MODEL=qwen3-8b-opencode:latest ./setup-opencode.sh
```

Point at a remote Ollama instance:

```bash
OLLAMA_URL=http://192.168.1.10:11434 ./setup-opencode.sh
```

## Config highlights

From `opencode.json`:

| Key | Value | Notes |
|-----|-------|-------|
| `enabled_providers` | `["ollama"]` | Local only |
| `model` | `ollama/qwen3-coder-30b-opencode:latest` | Overwritten by setup script |
| `provider.ollama.options.baseURL` | `http://localhost:11434/v1` | OpenAI-compatible API |
| `provider.ollama.options.timeout` | `600000` | 10-minute request timeout |
| `provider.ollama.options.chunkTimeout` | `120000` | 2-minute chunk timeout |
| `agent.build.prompt` | long-running bash hint | Suggests 10m timeouts for builds |
| `permission.external_directory` | `~/scratch/**` allow | Permits access outside project root |

Registered models in config:

- `qwen3-coder-30b-opencode:latest` — primary
- `qwen3-8b-opencode:latest` — fallback
- `llama3.2-opencode:latest` — fallback

Each has `tools: true` and 64k context / 16k output limits.

## Bash timeouts

`opencode.sh` and `run-opencode.sh` set:

```bash
export OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS=600000
```

Override for shorter commands:

```bash
OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS=120000 ./opencode.sh
```

## Troubleshooting

**"Ollama is not reachable"** — run `./start.sh` first.

**"Model not found"** — run `./setup-model.sh`.

**Tools not executing** — confirm you are on a `qwen3-coder` model with native renderer/parser, not qwen2.5-coder.

## Related

- [Interactive TUI](interactive-tui.md)
- [Non-interactive runner](non-interactive-runner.md)
- [Model setup](model-setup.md)

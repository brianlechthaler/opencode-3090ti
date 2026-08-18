# Getting started

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| NVIDIA GPU | 24 GB VRAM for the default Qwen3.8 27B model |
| Docker | Engine + Compose plugin |
| NVIDIA Container Toolkit | Required for `gpus: all` in Docker Compose |
| curl, python3 | Used by setup scripts |

### Install NVIDIA Container Toolkit

If `docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi` fails:

```bash
./install-nvidia-container-toolkit.sh
```

This script adds the NVIDIA apt repo, installs `nvidia-container-toolkit`, configures the Docker runtime, and restarts Docker.

### Docker group access

If Docker requires sudo, either add your user to the `docker` group:

```bash
sudo usermod -aG docker "$USER"
# log out and back in
```

Or run scripts from a terminal where sudo can prompt for a password.

## First-time setup

### Option A — interactive (repo checkout)

```bash
./start.sh           # starts Ollama on http://localhost:11434
./setup-model.sh     # pulls qwen3.8 and creates qwen3.8-opencode
./setup-opencode.sh  # installs OpenCode CLI and copies opencode.json
```

### Option B — unattended host install

Installs under `/opt/opencode-3090ti`, starts Ollama on boot, and refreshes the stack every 6 hours:

```bash
curl -fsSL https://raw.githubusercontent.com/brianlechthaler/opencode-3090ti/main/scripts/install.sh | sudo bash
cd /opt/opencode-3090ti
./setup-model.sh
./setup-opencode.sh
```

See [Auto-updates](features/auto-updates.md).

`setup-model.sh` also creates `llama3.2-opencode` immediately (no download) so you have a working fallback while the 27B model pulls.

## Run OpenCode

**Interactive TUI** (from a project directory, not `~`):

```bash
cd ~/Projects/my-app
/path/to/opencode-3090ti/opencode.sh
```

**Non-interactive** (scripts, CI):

```bash
./run-opencode.sh "add unit tests for the auth module"
```

## Verify Ollama

```bash
curl http://localhost:11434/api/tags
docker compose exec ollama ollama list
```

## Environment variables

| Variable | Default | Used by |
|----------|---------|---------|
| `OLLAMA_URL` | `http://localhost:11434` | `setup-opencode.sh`, `run-opencode.sh` |
| `OPENCODE_MODEL` | `qwen3.8-opencode:latest` | `setup-opencode.sh`, `setup-model.sh` |
| `OLLAMA_MODEL` | `qwen3.8:latest` | `setup-model.sh` |
| `OLLAMA_CUSTOM_MODEL` | `qwen3.8-opencode` | `setup-model.sh` |
| `OLLAMA_MODELFILE` | `Modelfile.qwen3.8` | `setup-model.sh` |
| `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS` | `600000` | `opencode.sh`, `run-opencode.sh` |

## Troubleshooting

### Ollama not reachable

Start the stack: `./start.sh`. Check `docker compose ps` and `docker compose logs ollama`.

### Model pull stalls

`setup-model.sh` retries pulls with a 300-second timeout per attempt and resumes partial downloads (`OLLAMA_NOPRUNE=1`). Re-run the script to continue.

### Out of GPU memory

The default stack sets `OLLAMA_KV_CACHE_TYPE=q8_0` and `OLLAMA_CONTEXT_LENGTH=65536` to fit 27B weights plus 64k context in 24 GB. If you still OOM:

- Use a smaller model: `OLLAMA_MODEL=qwen3:8b OLLAMA_CUSTOM_MODEL=qwen3-8b-opencode OLLAMA_MODELFILE=Modelfile.qwen3 ./setup-model.sh`
- Reduce context in the Modelfile and recreate the model

### OpenCode can't call tools

Use `qwen3-coder` with `RENDERER qwen3-coder` and `PARSER qwen3-coder` in the Modelfile. Qwen2.5 Coder emits tool JSON in message content, which OpenCode cannot execute.

### `opencode run` hangs without a TTY

`run-opencode.sh` allocates a pseudo-TTY via `script` when stdout is not a terminal. Install `bsdutils` (provides `script`) if missing.

## Related

- [Architecture](architecture.md)
- [Model setup](features/model-setup.md)
- [OpenCode configuration](features/opencode-config.md)

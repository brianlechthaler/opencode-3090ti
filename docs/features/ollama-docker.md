# Ollama Docker stack

Runs Ollama in Docker with full GPU access and settings tuned for 24 GB VRAM.

## Overview

`docker-compose.yml` starts a single `ollama` service:

- Image: `ollama/ollama:latest`
- Port: `11434` (host and container)
- Volume: `ollama_data` persists model weights across restarts
- GPU: `gpus: all` with `NVIDIA_VISIBLE_DEVICES=all`

## Configuration

| Env var | Value | Purpose |
|---------|-------|---------|
| `OLLAMA_NUM_GPU` | `999` | Offload all layers to GPU; fail instead of CPU spill |
| `OLLAMA_FLASH_ATTENTION` | `1` | Enable flash attention |
| `OLLAMA_NOPRUNE` | `1` | Keep partial downloads on restart |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | Reduce KV cache memory |
| `OLLAMA_CONTEXT_LENGTH` | `65536` | Server-wide 64k context default |

## Usage

```bash
./start.sh                    # alias for setup-and-start.sh
docker compose up -d          # equivalent
docker compose logs -f ollama # follow logs
docker compose down           # stop (volume kept)
```

`docker-compose.gpu.yml` is a no-op overlay kept for backwards compatibility with:

```bash
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
```

GPU settings now live in the main compose file.

## Troubleshooting

**Docker can't see GPU** — run `./install-nvidia-container-toolkit.sh`, then test:

```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

**Permission denied on Docker socket** — add user to `docker` group or use sudo (scripts auto-detect).

## Related

- [Getting started](../getting-started.md)
- [Model setup](model-setup.md)

# opencode-3090ti

Run [OpenCode](https://opencode.ai) against local Ollama models on an NVIDIA GPU (tuned for a 24 GB RTX 3090 Ti). Pulls Qwen3 Coder 30B with native tool calling, 64k context, and 10-minute bash timeouts for docker builds.

## Quick start

```bash
./install-nvidia-container-toolkit.sh   # once, if Docker can't see the GPU
./start.sh                              # start Ollama in Docker
./setup-model.sh                        # pull and create the coding model (~18 GB)
./setup-opencode.sh                     # install OpenCode and copy config
./opencode.sh                           # interactive TUI
```

See [Getting started](docs/getting-started.md) for prerequisites, troubleshooting, and alternative models.

## Unattended install + auto-updates

Mirror of the [remote-tools](https://github.com/brianlechthaler/remote-tools) update pattern:

- Weekly GitHub Action bumps the pinned `ollama/ollama` image when Docker Hub has a newer stable release
- Host systemd timer pulls this repo and refreshes containers every 6 hours

```bash
curl -fsSL https://raw.githubusercontent.com/brianlechthaler/opencode-3090ti/main/scripts/install.sh | sudo bash
```

Pinned image: `ollama/ollama:0.32.13`. Details: [Auto-updates](docs/features/auto-updates.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Features](docs/features/)
  - [Ollama Docker stack](docs/features/ollama-docker.md)
  - [Auto-updates](docs/features/auto-updates.md)
  - [Model setup](docs/features/model-setup.md)
  - [OpenCode configuration](docs/features/opencode-config.md)
  - [Interactive TUI](docs/features/interactive-tui.md)
  - [Non-interactive runner](docs/features/non-interactive-runner.md)

## Requirements

- Linux with NVIDIA GPU (24 GB VRAM recommended for the default 30B model)
- Docker with GPU support (NVIDIA Container Toolkit)
- ~20 GB disk for the default model weights

## License

No license specified.

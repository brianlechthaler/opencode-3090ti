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

## Documentation

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Features](docs/features/)
  - [Ollama Docker stack](docs/features/ollama-docker.md)
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

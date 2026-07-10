# Interactive TUI

Launches the OpenCode terminal UI with long bash timeouts for docker and compile jobs.

## Overview

`opencode.sh` is a thin wrapper around the `opencode` CLI. It adds `~/.opencode/bin` to `PATH`, sets a 10-minute default bash timeout, and passes through all arguments.

## Usage

Run from a project directory (not your home directory):

```bash
cd ~/Projects/my-app
~/Projects/opencode-3090ti/opencode.sh
```

Pass OpenCode flags as usual:

```bash
./opencode.sh --help
```

## Prerequisites

1. OpenCode installed: `./setup-opencode.sh`
2. Ollama running with the configured model: `./start.sh` and `./setup-model.sh`

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS` | `600000` | Bash tool timeout (10 minutes) |

## Troubleshooting

**"OpenCode not installed"** — run `./setup-opencode.sh`.

**Slow or empty responses** — check `curl http://localhost:11434/api/tags` and GPU load with `nvidia-smi`.

## Related

- [OpenCode configuration](opencode-config.md)
- [Non-interactive runner](non-interactive-runner.md)

# Non-interactive runner

Runs `opencode run --auto` from scripts or CI with automatic TTY allocation.

## Overview

`opencode run` needs a TTY for skill initialization. Without one it can hang ~60 seconds and exit without running the agent loop. `run-opencode.sh` detects non-TTY stdout and wraps the call with `script` to allocate a pseudo-terminal.

## Usage

```bash
./run-opencode.sh "add error handling to the upload endpoint"
```

From another script:

```bash
/path/to/opencode-3090ti/run-opencode.sh "run the test suite and fix failures"
```

When stdout is already a terminal, it runs `opencode` directly.

## Prerequisites

Same as the interactive TUI:

1. `./setup-opencode.sh`
2. Ollama running (`./start.sh`)

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_URL` | `http://localhost:11434` | Ollama health check URL |
| `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS` | `600000` | Bash tool timeout |

## Troubleshooting

**Hang with no output in CI** — install `bsdutils` (provides the `script` command). Without it, the script prints a warning and may still hang.

**"Ollama is not running"** — start the stack with `./start.sh`.

## Related

- [Interactive TUI](interactive-tui.md)
- [OpenCode configuration](opencode-config.md)

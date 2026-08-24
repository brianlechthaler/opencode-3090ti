# Auto-updates

Keeps the host on the latest repo stack and the latest stable Ollama image.

## Ollama version bumps (GitHub Actions)

`.github/workflows/ollama-version-bump.yml` runs weekly (Mondays 09:00 UTC) and on demand:

1. Compares the pinned tag in `docker-compose.yml` with the newest stable Ollama GitHub release (`scripts/ollama-version.sh`; maps to `ollama/ollama:<semver>` on Docker Hub)
2. Opens a PR that bumps `docker-compose.yml` (and docs) when a newer release exists
3. Labels the PR `automerge` so CI can squash-merge it after checks pass

Pinned image today: `ollama/ollama:0.32.15`

Manual check:

```bash
./scripts/ollama-version.sh current
./scripts/ollama-version.sh latest
```

## Host updater (every 6 hours)

After a one-time install, systemd pulls this repo and refreshes containers on a timer.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/brianlechthaler/opencode-3090ti/main/scripts/install.sh | sudo bash
```

Or from a checkout:

```bash
sudo ./scripts/install.sh
```

This clones/updates `/opt/opencode-3090ti`, installs systemd units, starts Ollama, and enables the update timer.

### What the timer does

`opencode-3090ti-update.timer` fires about every 6 hours (`OnUnitActiveSec=6h`, plus boot delay and jitter). It runs `scripts/update.sh`, which:

1. `git fetch` + `reset --hard` to `origin/main` (override with `BRANCH=...`)
2. Reloads systemd unit files from the repo
3. `docker compose pull` for the pinned Ollama image
4. `docker compose up -d --remove-orphans`

So when an Ollama bump lands on `main`, hosts pick it up on the next timer tick (or immediately via a manual update).

### Operations

```bash
systemctl status opencode-3090ti
systemctl list-timers 'opencode-3090ti-*'
journalctl -u opencode-3090ti-update -f

# Same path as the timer
sudo /opt/opencode-3090ti/scripts/update.sh

# Optional: install/test a PR branch before it lands on main
sudo BRANCH=cursor/some-branch /opt/opencode-3090ti/scripts/update.sh
```

## Related

- [Ollama Docker stack](ollama-docker.md)
- [Getting started](../getting-started.md)
- [Architecture](../architecture.md)

## Testing

```bash
./scripts/test-all.sh              # static + version + update dry-run + Ollama startup
SKIP_STARTUP=1 ./scripts/test-all.sh
```

CI runs these on every PR/push and daily via `.github/workflows/test.yml`.


#!/usr/bin/env bash
# Static checks: syntax, shellcheck, compose, docs pin consistency, systemd units.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

echo "== shell syntax =="
shopt -s nullglob
scripts=(*.sh scripts/*.sh)
[[ ${#scripts[@]} -gt 0 ]] || fail "no shell scripts found"
for script in "${scripts[@]}"; do
  bash -n "${script}" || fail "bash -n ${script}"
done
pass "bash -n for ${#scripts[@]} scripts"

echo
echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${scripts[@]}" || fail "shellcheck reported issues"
  pass "shellcheck clean"
else
  fail "shellcheck is not installed"
fi

echo
echo "== required files =="
required=(
  docker-compose.yml
  docker-compose.gpu.yml
  docker-compose.ci.yml
  docker-compose.vllm.yml
  opencode.json
  benchmark-ollama.json
  ollama_performance_summary.md
  Modelfile.qwen3.8
  Modelfile.qwen3-coder
  Modelfile.qwen3
  Modelfile.qwen2.5-coder-14b
  Modelfile.llama
  benchmark.sh
  install-nvidia-container-toolkit.sh
  opencode.sh
  pull-model-vllm.sh
  run-opencode.sh
  setup-and-start.sh
  setup-model.sh
  setup-opencode.sh
  start.sh
  start-vllm.sh
  scripts/install.sh
  scripts/update.sh
  scripts/start.sh
  scripts/ollama-version.sh
  scripts/lint-all.sh
  scripts/test-all.sh
  scripts/test-coverage.sh
  scripts/test-scripts-smoke.sh
  scripts/test-start-stack.sh
  scripts/test-static.sh
  scripts/test-ollama-version.sh
  scripts/test-update-dry.sh
  scripts/test-ollama-startup.sh
  systemd/opencode-3090ti.service
  systemd/opencode-3090ti-update.service
  systemd/opencode-3090ti-update.timer
  docs/architecture.md
  docs/getting-started.md
  docs/features/auto-updates.md
  docs/features/interactive-tui.md
  docs/features/model-setup.md
  docs/features/non-interactive-runner.md
  docs/features/ollama-docker.md
  docs/features/opencode-config.md
  .github/workflows/test.yml
  .github/workflows/lint.yml
  .github/workflows/container.yml
  .github/workflows/ollama-version-bump.yml
)
for path in "${required[@]}"; do
  [[ -e "${path}" ]] || fail "missing ${path}"
done
pass "required project files exist"

echo
echo "== JSON files =="
python3 -m json.tool opencode.json >/dev/null || fail "opencode.json is invalid JSON"
python3 -m json.tool benchmark-ollama.json >/dev/null || fail "benchmark-ollama.json is invalid JSON"
pass "JSON files are valid"

echo
echo "== Modelfile directives =="
for mf in Modelfile.qwen3.8 Modelfile.qwen3-coder Modelfile.qwen3 Modelfile.qwen2.5-coder-14b Modelfile.llama; do
  grep -qE '^FROM ' "${mf}" || fail "${mf} missing FROM"
  grep -qE '^PARAMETER num_ctx ' "${mf}" || fail "${mf} missing PARAMETER num_ctx"
done
grep -qE '^RENDERER qwen3-coder$' Modelfile.qwen3-coder || fail "Modelfile.qwen3-coder missing RENDERER"
grep -qE '^PARSER qwen3-coder$' Modelfile.qwen3-coder || fail "Modelfile.qwen3-coder missing PARSER"
pass "Modelfiles have expected directives"

echo
echo "== docker compose config =="
docker compose -f docker-compose.yml config --quiet || fail "compose config failed"
docker compose -f docker-compose.yml -f docker-compose.gpu.yml config --quiet || fail "gpu overlay config failed"
docker compose -f docker-compose.yml -f docker-compose.ci.yml config --quiet || fail "ci overlay config failed"
docker compose -f docker-compose.vllm.yml config --quiet || fail "vllm compose config failed"
pass "compose configs render"

echo
echo "== pinned Ollama image consistency =="
pinned="$(bash scripts/ollama-version.sh current)"
[[ "${pinned}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid pinned version '${pinned}'"
grep -q "image: ollama/ollama:${pinned}" docker-compose.yml || fail "compose pin mismatch"
grep -q "ollama/ollama:${pinned}" README.md || fail "README pin mismatch"
grep -q "ollama/ollama:${pinned}" docs/features/ollama-docker.md || fail "ollama-docker.md pin mismatch"
grep -q "ollama/ollama:${pinned}" docs/features/auto-updates.md || fail "auto-updates.md pin mismatch"
# Ensure we are not still advertising :latest as the production image.
if grep -nE 'image: ollama/ollama:latest' docker-compose.yml; then
  fail "docker-compose.yml still uses :latest"
fi
pass "pinned version ${pinned} is consistent across compose + docs"

echo
echo "== systemd units =="
grep -q 'ExecStart=/opt/opencode-3090ti/scripts/start.sh' systemd/opencode-3090ti.service \
  || fail "start service ExecStart mismatch"
grep -q 'ExecStart=/opt/opencode-3090ti/scripts/update.sh' systemd/opencode-3090ti-update.service \
  || fail "update service ExecStart mismatch"
grep -q 'OnUnitActiveSec=6h' systemd/opencode-3090ti-update.timer \
  || fail "update timer is not every 6 hours"
grep -q 'WantedBy=timers.target' systemd/opencode-3090ti-update.timer \
  || fail "update timer missing WantedBy=timers.target"
pass "systemd units reference expected scripts and 6h timer"

echo
echo "== workflow YAML =="
python3 - <<'PY' || fail "workflow YAML failed to parse"
import glob
import sys

try:
    import yaml
except ImportError:
    print("FAIL: PyYAML is required to validate workflow files", file=sys.stderr)
    sys.exit(1)

class TolerantLoader(yaml.SafeLoader):
    pass

def _unknown_tag(loader, tag_suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node)
    return None

TolerantLoader.add_multi_constructor("!", _unknown_tag)

paths = sorted(glob.glob(".github/workflows/*.yml"))
if not paths:
    print("FAIL: no workflow files found", file=sys.stderr)
    sys.exit(1)

for path in paths:
    with open(path, encoding="utf-8") as handle:
        yaml.load(handle, Loader=TolerantLoader)
    print(f"parsed {path}")
PY
pass "workflow YAML parses"

echo
echo "== workflow coverage =="
grep -q 'name: Bump Ollama' .github/workflows/ollama-version-bump.yml \
  || fail "version bump workflow missing"
grep -q 'schedule:' .github/workflows/test.yml || fail "test workflow missing schedule for continuous runs"
for script in \
  scripts/lint-all.sh \
  scripts/test-static.sh \
  scripts/test-ollama-startup.sh \
  scripts/test-update-dry.sh \
  scripts/test-ollama-version.sh \
  scripts/test-scripts-smoke.sh \
  scripts/test-start-stack.sh \
  scripts/test-coverage.sh
do
  grep -q "${script}" .github/workflows/test.yml \
    || fail "test workflow does not invoke ${script}"
done
grep -q 'scripts/lint-all.sh' .github/workflows/lint.yml || fail "lint.yml missing lint-all.sh"
pass "GitHub workflows cover continuous testing"

echo
echo "Static tests passed"

#!/usr/bin/env bash
# Fail unless every tracked project file is inventoried with lint + test coverage.
#
# This is the 100% coverage gate: the manifest below is the source of truth.
# Adding a new file without updating this map (and a covering test) fails CI.
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

# path|linted_by|tested_by
# linted_by / tested_by are comma-separated script names (or "-" if N/A).
MANIFEST=$(cat <<'EOF'
.gitignore|-|test-coverage.sh
README.md|lint-all.sh|test-static.sh
docker-compose.yml|lint-all.sh|test-static.sh,test-ollama-startup.sh
docker-compose.gpu.yml|lint-all.sh|test-static.sh
docker-compose.ci.yml|lint-all.sh|test-static.sh,test-ollama-startup.sh
opencode.json|lint-all.sh|test-static.sh,test-scripts-smoke.sh
Modelfile.llama|lint-all.sh|test-static.sh,test-scripts-smoke.sh
Modelfile.qwen2.5-coder-14b|lint-all.sh|test-static.sh,test-scripts-smoke.sh
Modelfile.qwen3|lint-all.sh|test-static.sh,test-scripts-smoke.sh
Modelfile.qwen3-coder|lint-all.sh|test-static.sh,test-scripts-smoke.sh
install-nvidia-container-toolkit.sh|lint-all.sh|test-scripts-smoke.sh
opencode.sh|lint-all.sh|test-scripts-smoke.sh
run-opencode.sh|lint-all.sh|test-scripts-smoke.sh
setup-and-start.sh|lint-all.sh|test-scripts-smoke.sh
setup-model.sh|lint-all.sh|test-scripts-smoke.sh
setup-opencode.sh|lint-all.sh|test-scripts-smoke.sh
start.sh|lint-all.sh|test-scripts-smoke.sh
scripts/install.sh|lint-all.sh|test-update-dry.sh,test-scripts-smoke.sh
scripts/lint-all.sh|lint-all.sh|test-coverage.sh
scripts/ollama-version.sh|lint-all.sh|test-ollama-version.sh
scripts/start.sh|lint-all.sh|test-start-stack.sh
scripts/update.sh|lint-all.sh|test-update-dry.sh
scripts/test-all.sh|lint-all.sh|test-coverage.sh
scripts/test-coverage.sh|lint-all.sh|test-coverage.sh
scripts/test-ollama-startup.sh|lint-all.sh|test-coverage.sh
scripts/test-ollama-version.sh|lint-all.sh|test-coverage.sh
scripts/test-scripts-smoke.sh|lint-all.sh|test-coverage.sh
scripts/test-start-stack.sh|lint-all.sh|test-coverage.sh
scripts/test-static.sh|lint-all.sh|test-coverage.sh
scripts/test-update-dry.sh|lint-all.sh|test-coverage.sh
systemd/opencode-3090ti.service|lint-all.sh|test-static.sh,test-start-stack.sh
systemd/opencode-3090ti-update.service|lint-all.sh|test-static.sh
systemd/opencode-3090ti-update.timer|lint-all.sh|test-static.sh
.github/workflows/container.yml|lint-all.sh|test-static.sh
.github/workflows/lint.yml|lint-all.sh|test-static.sh,test-coverage.sh
.github/workflows/ollama-version-bump.yml|lint-all.sh|test-static.sh,test-ollama-version.sh
.github/workflows/test.yml|lint-all.sh|test-static.sh,test-coverage.sh
docs/architecture.md|-|test-static.sh
docs/getting-started.md|-|test-static.sh
docs/features/auto-updates.md|-|test-static.sh
docs/features/interactive-tui.md|-|test-static.sh
docs/features/model-setup.md|-|test-static.sh
docs/features/non-interactive-runner.md|-|test-static.sh
docs/features/ollama-docker.md|-|test-static.sh
docs/features/opencode-config.md|-|test-static.sh
EOF
)

echo "== coverage manifest integrity =="
declare -A seen=()
while IFS='|' read -r path linted tested; do
  [[ -n "${path}" ]] || continue
  [[ -e "${path}" ]] || fail "manifest lists missing file: ${path}"
  [[ -n "${linted}" && -n "${tested}" ]] || fail "manifest row incomplete for ${path}"
  if [[ -n "${seen[${path}]+x}" ]]; then
    fail "duplicate manifest entry: ${path}"
  fi
  seen["${path}"]=1

  if [[ "${linted}" != "-" ]]; then
    IFS=',' read -r -a lint_by <<<"${linted}"
    for tool in "${lint_by[@]}"; do
      [[ -f "scripts/${tool}" || -f "${tool}" ]] || fail "${path}: lint tool scripts/${tool} missing"
    done
  fi
  IFS=',' read -r -a test_by <<<"${tested}"
  for tool in "${test_by[@]}"; do
    [[ -f "scripts/${tool}" ]] || fail "${path}: covering test scripts/${tool} missing"
  done
done <<<"${MANIFEST}"
pass "manifest rows are valid (${#seen[@]} files)"

echo "== no project files outside manifest =="
mapfile -t tracked < <(
  {
    git ls-files
    git ls-files --others --exclude-standard
  } | sort -u
)
missing=()
for path in "${tracked[@]}"; do
  # Ignore paths outside the project inventory (none expected).
  if [[ -z "${seen[${path}]+x}" ]]; then
    missing+=("${path}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Uncovered project file(s):\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  fail "add each file to scripts/test-coverage.sh MANIFEST with lint+test owners"
fi
pass "every project file is in the coverage manifest (${#tracked[@]} files)"

echo
echo "== required CI wiring =="
for needle in \
  'scripts/lint-all.sh' \
  'scripts/test-coverage.sh' \
  'scripts/test-scripts-smoke.sh' \
  'scripts/test-start-stack.sh' \
  'scripts/test-static.sh' \
  'scripts/test-ollama-version.sh' \
  'scripts/test-update-dry.sh' \
  'scripts/test-ollama-startup.sh'
do
  grep -q "${needle}" .github/workflows/test.yml \
    || grep -q "${needle}" .github/workflows/lint.yml \
    || fail "CI does not invoke ${needle}"
done
grep -q 'scripts/lint-all.sh' .github/workflows/lint.yml || fail "lint.yml must call lint-all.sh"
grep -q 'scripts/test-coverage.sh' .github/workflows/test.yml || fail "test.yml must call test-coverage.sh"
pass "CI invokes lint + full test suite"

echo
echo "== lint/test self-coverage =="
# Every scripts/*.sh must appear in the manifest.
mapfile -t script_files < <(find scripts -type f -name '*.sh' | sed 's|^\./||' | sort)
for path in "${script_files[@]}"; do
  [[ -n "${seen[${path}]+x}" ]] || fail "scripts file not in manifest: ${path}"
done
pass "all scripts/*.sh are inventoried"

echo
echo "100% coverage gate passed (${#tracked[@]} tracked files)"

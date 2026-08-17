#!/usr/bin/env bash
# Lint every shell script, workflow, compose file, and JSON config in the repo.
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

shopt -s nullglob globstar

echo "== collect shell scripts =="
mapfile -t scripts < <(find . -type f -name '*.sh' ! -path './.git/*' | sed 's|^\./||' | sort)
[[ ${#scripts[@]} -gt 0 ]] || fail "no shell scripts found"
printf '  %s\n' "${scripts[@]}"
pass "found ${#scripts[@]} shell scripts"

echo
echo "== bash -n =="
for script in "${scripts[@]}"; do
  bash -n "${script}" || fail "bash -n ${script}"
done
pass "bash -n clean"

echo
echo "== shellcheck =="
command -v shellcheck >/dev/null || fail "shellcheck is not installed"
# SC1091: ignore optional external sources; scripts are self-contained.
shellcheck --severity=style --exclude=SC1091 "${scripts[@]}" || fail "shellcheck reported issues"
pass "shellcheck clean (${#scripts[@]} scripts)"

echo
echo "== executable bits =="
for script in "${scripts[@]}"; do
  [[ -x "${script}" ]] || fail "${script} is not executable"
done
pass "all shell scripts are executable"

echo
echo "== YAML (workflows + compose) =="
mapfile -t yamls < <(
  {
    find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \)
    find . -maxdepth 1 -type f \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \)
  } | sed 's|^\./||' | sort -u
)
[[ ${#yamls[@]} -gt 0 ]] || fail "no YAML files found"
python3 - <<'PY' || fail "YAML lint failed"
import glob
import sys

try:
    import yaml
except ImportError:
    print("FAIL: PyYAML required", file=sys.stderr)
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

paths = sorted(
    glob.glob(".github/workflows/*.[yY][mM][lL]")
    + glob.glob("docker-compose*.yml")
    + glob.glob("docker-compose*.yaml")
)
if not paths:
    print("FAIL: no YAML files", file=sys.stderr)
    sys.exit(1)

for path in paths:
    with open(path, encoding="utf-8") as handle:
        docs = list(yaml.load_all(handle, Loader=TolerantLoader))
    if not docs or all(doc is None for doc in docs):
        print(f"FAIL: {path} is empty", file=sys.stderr)
        sys.exit(1)
    print(f"ok {path}")
PY
pass "YAML files parse (${#yamls[@]} files)"

echo
echo "== actionlint (workflows) =="
if command -v actionlint >/dev/null 2>&1; then
  actionlint -color .github/workflows/*.yml || fail "actionlint reported issues"
  pass "actionlint clean"
else
  # Install a pinned actionlint when missing (CI + local).
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) fail "unsupported arch for actionlint: ${arch}" ;;
  esac
  ver="1.7.7"
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ver}/actionlint_${ver}_linux_${arch}.tar.gz" \
    | tar -xz -C "${tmp}" actionlint
  "${tmp}/actionlint" -color .github/workflows/*.yml || fail "actionlint reported issues"
  rm -rf "${tmp}"
  pass "actionlint clean (downloaded v${ver})"
fi

echo
echo "== JSON =="
for json_file in opencode.json benchmark-ollama.json; do
  python3 -m json.tool "${json_file}" >/dev/null || fail "${json_file} invalid"
done
pass "JSON files valid"

echo
echo "== Modelfiles =="
mapfile -t modelfiles < <(find . -maxdepth 1 -type f -name 'Modelfile*' | sed 's|^\./||' | sort)
[[ ${#modelfiles[@]} -gt 0 ]] || fail "no Modelfiles found"
for mf in "${modelfiles[@]}"; do
  grep -qE '^FROM[[:space:]]+' "${mf}" || fail "${mf} missing FROM"
  grep -qE '^PARAMETER[[:space:]]+num_ctx[[:space:]]+' "${mf}" || fail "${mf} missing num_ctx"
done
pass "Modelfiles linted (${#modelfiles[@]} files)"

echo
echo "== systemd unit basics =="
for unit in systemd/*.service systemd/*.timer; do
  grep -q '^\[Unit\]' "${unit}" || fail "${unit} missing [Unit]"
done
for unit in systemd/*.timer systemd/opencode-3090ti.service; do
  grep -q '^\[Install\]' "${unit}" || fail "${unit} missing [Install]"
done
# Timer-triggered oneshots intentionally omit [Install]; the timer enables them.
grep -q '^Type=oneshot$' systemd/opencode-3090ti-update.service \
  || fail "update service should be Type=oneshot"
pass "systemd units have required sections"

echo
echo "All lint checks passed"

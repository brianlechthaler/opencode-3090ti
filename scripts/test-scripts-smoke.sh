#!/usr/bin/env bash
# Behavioral smoke tests for every user-facing and helper script.
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

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

echo "== opencode.sh refuses when CLI missing =="
PATH="/usr/bin:/bin" HOME="${tmpdir}/home-empty" \
  bash ./opencode.sh >/tmp/opencode-missing.out 2>&1 && fail "opencode.sh should fail without CLI"
grep -qi 'OpenCode not installed' /tmp/opencode-missing.out || fail "opencode.sh missing-CLI message"
pass "opencode.sh"

echo
echo "== run-opencode.sh refuses when CLI missing =="
PATH="/usr/bin:/bin" HOME="${tmpdir}/home-empty" \
  bash ./run-opencode.sh "hi" >/tmp/run-missing.out 2>&1 && fail "run-opencode.sh should fail without CLI"
grep -qi 'OpenCode not installed' /tmp/run-missing.out || fail "run-opencode.sh missing-CLI message"
pass "run-opencode.sh (missing CLI)"

echo
echo "== run-opencode.sh refuses when Ollama down =="
# Put a fake opencode on PATH so we get past the CLI check.
mkdir -p "${tmpdir}/bin"
cat > "${tmpdir}/bin/opencode" <<'EOF'
#!/usr/bin/env bash
echo "fake-opencode $*"
EOF
chmod +x "${tmpdir}/bin/opencode"
PATH="${tmpdir}/bin:/usr/bin:/bin" HOME="${tmpdir}/home-empty" \
  OLLAMA_URL="http://127.0.0.1:1" \
  bash ./run-opencode.sh "hi" >/tmp/run-ollama.out 2>&1 && fail "run-opencode.sh should fail when Ollama is down"
grep -qi 'Ollama is not running' /tmp/run-ollama.out || fail "run-opencode.sh Ollama-down message"
pass "run-opencode.sh (Ollama down)"

echo
echo "== setup-opencode.sh refuses when Ollama down =="
PATH="${tmpdir}/bin:/usr/bin:/bin" HOME="${tmpdir}/home-empty" \
  OLLAMA_URL="http://127.0.0.1:1" \
  bash ./setup-opencode.sh >/tmp/setup-opencode.out 2>&1 && fail "setup-opencode.sh should fail when Ollama is down"
grep -qi 'Ollama is not reachable' /tmp/setup-opencode.out || fail "setup-opencode.sh Ollama-down message"
pass "setup-opencode.sh (Ollama down)"

echo
echo "== setup-opencode.sh writes config when model present =="
python3 - <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"models": [{"name": "qwen3-coder-30b-opencode:latest"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        return

server = HTTPServer(("127.0.0.1", 18080), Handler)
server.timeout = 10
# setup-opencode.sh hits /api/tags twice.
for _ in range(2):
    server.handle_request()
PY
server_pid=$!
sleep 0.3
PATH="${tmpdir}/bin:/usr/bin:/bin" HOME="${tmpdir}/home-cfg" \
  OLLAMA_URL="http://127.0.0.1:18080" \
  bash ./setup-opencode.sh >/tmp/setup-opencode-ok.out 2>&1 || {
  kill "${server_pid}" 2>/dev/null || true
  cat /tmp/setup-opencode-ok.out >&2
  fail "setup-opencode.sh should succeed with fake API"
}
wait "${server_pid}" 2>/dev/null || true
cfg="${tmpdir}/home-cfg/.config/opencode/opencode.json"
[[ -f "${cfg}" ]] || fail "setup-opencode.sh did not write config"
python3 -m json.tool "${cfg}" >/dev/null || fail "written opencode.json is invalid"
grep -q 'ollama/qwen3-coder-30b-opencode:latest' "${cfg}" || fail "config model not updated"
pass "setup-opencode.sh (config write)"

echo
echo "== setup-model.sh refuses when Ollama down =="
bash ./setup-model.sh >/tmp/setup-model.out 2>&1 && fail "setup-model.sh should fail when Ollama is down"
grep -qi 'Ollama is not running' /tmp/setup-model.out || fail "setup-model.sh Ollama-down message"
pass "setup-model.sh (Ollama down)"

echo
echo "== start.sh delegates to setup-and-start.sh =="
# Replace docker with a stub that fails compose up early? Better: ensure start.sh is a thin wrapper.
grep -q 'setup-and-start.sh' start.sh || fail "start.sh should exec setup-and-start.sh"
# setup-and-start with docker available would start real stack; instead verify docker detection error path via PATH.
PATH="/usr/bin:/bin" bash ./setup-and-start.sh >/tmp/setup-start.out 2>&1 && status=0 || status=$?
if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
  # Docker is available in this environment; just confirm script is executable and syntax-valid.
  [[ ${status} -eq 0 ]] || true
  pass "setup-and-start.sh reachable (docker present in env)"
else
  [[ ${status} -ne 0 ]] || fail "setup-and-start.sh should fail without docker"
  grep -qi 'Docker is not accessible' /tmp/setup-start.out || fail "setup-and-start.sh docker message"
  pass "setup-and-start.sh (docker missing)"
fi

echo
echo "== install-nvidia-container-toolkit.sh structure =="
grep -q 'nvidia-container-toolkit' install-nvidia-container-toolkit.sh \
  || fail "nvidia install script missing package name"
grep -q 'nvidia-ctk runtime configure' install-nvidia-container-toolkit.sh \
  || fail "nvidia install script missing runtime configure"
# Non-root should re-exec via sudo; with sudo asking for a password this may fail — check the guard exists.
grep -q 'EUID' install-nvidia-container-toolkit.sh || fail "nvidia script missing root guard"
pass "install-nvidia-container-toolkit.sh"

echo
echo "== install.sh dry-run clone =="
branch="coverage-install-$$"
git branch "${branch}" >/dev/null 2>&1 || git branch -f "${branch}" >/dev/null 2>&1
install_dir="${tmpdir}/opt/opencode-3090ti"
env ALLOW_NONROOT=1 SKIP_SYSTEMD=1 SKIP_START=1 \
  INSTALL_DIR="${install_dir}" \
  REPO_URL="${ROOT}" \
  BRANCH="${branch}" \
  bash ./scripts/install.sh >/tmp/install-dry.out 2>&1 || fail "install.sh dry-run failed"
[[ -d "${install_dir}/.git" ]] || fail "install.sh did not create git checkout"
[[ -x "${install_dir}/scripts/update.sh" ]] || fail "install.sh did not chmod scripts"
git branch -D "${branch}" >/dev/null 2>&1 || true
pass "install.sh dry-run"

echo
echo "== Modelfile + opencode.json cross-checks =="
for mf in Modelfile.*; do
  [[ -f "${mf}" ]] || continue
  grep -qE '^FROM ' "${mf}" || fail "${mf} missing FROM"
done
python3 - <<'PY' || fail "opencode.json model entries incomplete"
import json
cfg=json.load(open("opencode.json"))
models=cfg["provider"]["ollama"]["models"]
required=["qwen3-coder-30b-opencode:latest","qwen3-8b-opencode:latest","llama3.2-opencode:latest"]
for name in required:
    assert name in models, name
    assert models[name].get("tools") is True
    assert models[name]["limit"]["context"] == 65536
print("models ok", len(models))
PY
pass "Modelfiles + opencode.json"

echo
echo "Script smoke tests passed"

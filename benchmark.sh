#!/usr/bin/env bash
# Benchmark local LLM backends (vLLM or Ollama) for throughput and tool calling.
set -euo pipefail

cd "$(dirname "$0")"

BACKEND="${BACKEND:-auto}"
BASE_URL="${BASE_URL:-}"
MODEL="${MODEL:-}"
OUTPUT="${OUTPUT:-benchmark-results.json}"
WARMUP="${WARMUP:-1}"

usage() {
  cat <<'EOF'
Usage: ./benchmark.sh [options]

Environment:
  BACKEND   vllm | ollama | auto (default: auto)
  BASE_URL  Override API base (e.g. http://localhost:8000/v1)
  MODEL     Override model id
  OUTPUT    Results JSON path (default: benchmark-results.json)
  WARMUP    Warmup runs before timing (default: 1)

Examples:
  BACKEND=ollama ./benchmark.sh
  BACKEND=vllm BASE_URL=http://localhost:8000/v1 ./benchmark.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

detect_backend() {
  if [[ -n "$BASE_URL" ]]; then
    if [[ "$BASE_URL" == *":11434"* ]]; then
      BACKEND=ollama
    else
      BACKEND=vllm
    fi
    return
  fi
  if curl -fsS http://localhost:8000/health &>/dev/null || curl -fsS http://localhost:8000/v1/models &>/dev/null; then
    BACKEND=vllm
    BASE_URL="http://localhost:8000/v1"
  elif curl -fsS http://localhost:11434/api/tags &>/dev/null; then
    BACKEND=ollama
    BASE_URL="http://localhost:11434/v1"
  else
    echo "No LLM backend detected on :8000 or :11434."
    exit 1
  fi
}

resolve_model() {
  if [[ -n "$MODEL" ]]; then
    return
  fi
  if [[ "$BACKEND" == "ollama" ]]; then
    MODEL="$(curl -fsS http://localhost:11434/api/tags | python3 -c "
import json, sys
models = json.load(sys.stdin).get('models', [])
for m in models:
    name = m.get('name', '')
    if 'qwen3-coder' in name and 'opencode' in name:
        print(name)
        break
else:
    print(models[0]['name'] if models else 'qwen3-coder-30b-opencode:latest')
")"
  else
    MODEL="$(curl -fsS http://localhost:8000/v1/models | python3 -c "
import json, sys
data = json.load(sys.stdin)
ids = [m['id'] for m in data.get('data', [])]
for mid in ids:
    if 'Qwen3-Coder' in mid or 'qwen3-coder' in mid.lower():
        print(mid)
        break
else:
    print(ids[0] if ids else 'Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8')
")"
  fi
}

if [[ "$BACKEND" == "auto" ]]; then
  detect_backend
fi

if [[ -z "$BASE_URL" ]]; then
  if [[ "$BACKEND" == "ollama" ]]; then
    BASE_URL="http://localhost:11434/v1"
  else
    BASE_URL="http://localhost:8000/v1"
  fi
fi

resolve_model

echo "Backend: ${BACKEND}"
echo "Base URL: ${BASE_URL}"
echo "Model: ${MODEL}"
echo ""

python3 - "$BACKEND" "$BASE_URL" "$MODEL" "$OUTPUT" "$WARMUP" <<'PY'
import json
import sys
import time
import urllib.error
import urllib.request

backend, base_url, model, output_path, warmup = sys.argv[1:6]
warmup = int(warmup)

SYSTEM = (
    "You are a coding agent. Use absolute paths. Respond concisely."
)

SHORT_PROMPT = "Write a Python function that returns the nth Fibonacci number. Code only, no explanation."
MEDIUM_PROMPT = """Review this bash script and list three improvements:

#!/usr/bin/env bash
set -e
for f in $(find . -name '*.sh'); do
  bash -n $f
done
"""
LONG_PROMPT = """Analyze this module structure and suggest a refactor plan:

src/
  auth/
    login.rs
    session.rs
  api/
    routes.rs
    handlers.rs
  db/
    pool.rs
    migrations/
  lib.rs
  main.rs

Focus on separation of concerns and testability. Be specific."""

TOOL_PROMPT = "What is 17 * 23? Use the calculator tool."


def post_chat(payload, timeout=600):
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.loads(resp.read().decode())
    elapsed = time.perf_counter() - start
    return body, elapsed


def extract_text(body):
    choice = body.get("choices", [{}])[0]
    msg = choice.get("message", {})
    return msg.get("content") or ""


def count_tokens_estimate(text):
    return max(1, len(text.split()))


def run_completion(name, prompt, max_tokens=256, stream=False):
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
        "max_tokens": max_tokens,
        "stream": stream,
    }
    if stream:
        return run_stream(payload, name)
    body, elapsed = post_chat(payload)
    text = extract_text(body)
    usage = body.get("usage") or {}
    completion_tokens = usage.get("completion_tokens") or count_tokens_estimate(text)
    prompt_tokens = usage.get("prompt_tokens") or count_tokens_estimate(prompt)
    tps = completion_tokens / elapsed if elapsed > 0 else 0
    return {
        "name": name,
        "elapsed_s": round(elapsed, 3),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "tokens_per_second": round(tps, 2),
        "response_chars": len(text),
    }


def run_stream(payload, name):
    payload = dict(payload)
    payload["stream"] = True
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.perf_counter()
    ttft = None
    chunks = []
    completion_tokens = 0
    with urllib.request.urlopen(req, timeout=600) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if not line.startswith("data: "):
                continue
            data = line[6:]
            if data == "[DONE]":
                break
            chunk = json.loads(data)
            delta = chunk.get("choices", [{}])[0].get("delta", {})
            text = delta.get("content") or ""
            if text and ttft is None:
                ttft = time.perf_counter() - start
            if text:
                chunks.append(text)
                completion_tokens += max(1, len(text.split()) // 3)
    elapsed = time.perf_counter() - start
    if completion_tokens == 0:
        completion_tokens = count_tokens_estimate("".join(chunks))
    tps = completion_tokens / elapsed if elapsed > 0 else 0
    return {
        "name": name,
        "elapsed_s": round(elapsed, 3),
        "time_to_first_token_s": round(ttft or elapsed, 3),
        "completion_tokens": completion_tokens,
        "tokens_per_second": round(tps, 2),
        "response_chars": len("".join(chunks)),
        "streamed": True,
    }


def run_tool_call():
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": TOOL_PROMPT},
        ],
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "calculator",
                    "description": "Multiply two integers",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "a": {"type": "integer"},
                            "b": {"type": "integer"},
                        },
                        "required": ["a", "b"],
                    },
                },
            }
        ],
        "tool_choice": "auto",
        "temperature": 0.2,
        "max_tokens": 256,
    }
    body, elapsed = post_chat(payload)
    choice = body.get("choices", [{}])[0]
    msg = choice.get("message", {})
    tool_calls = msg.get("tool_calls") or []
    ok = False
    detail = ""
    if tool_calls:
        fn = tool_calls[0].get("function", {})
        args_raw = fn.get("arguments", "{}")
        try:
            args = json.loads(args_raw)
            if args.get("a") == 17 and args.get("b") == 23:
                ok = True
                detail = "correct tool call"
            else:
                detail = f"unexpected args: {args}"
        except json.JSONDecodeError:
            detail = f"invalid JSON args: {args_raw[:120]}"
    else:
        content = msg.get("content") or ""
        if "391" in content:
            detail = "answer in content, no native tool_calls"
        else:
            detail = "no tool_calls returned"
    return {
        "name": "tool_calling",
        "elapsed_s": round(elapsed, 3),
        "success": ok,
        "detail": detail,
        "tool_calls_count": len(tool_calls),
    }


results = {
    "backend": backend,
    "base_url": base_url,
    "model": model,
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "tests": [],
}

print("=== Warmup ===")
for i in range(warmup):
    try:
        run_completion(f"warmup-{i}", "Say OK.", max_tokens=8)
        print(f"  warmup {i + 1}/{warmup} done")
    except Exception as e:
        print(f"  warmup {i + 1} failed: {e}")

print("\n=== Benchmarks ===")
tests = [
    ("short_completion", SHORT_PROMPT, 256, False),
    ("medium_completion", MEDIUM_PROMPT, 512, False),
    ("long_prefill", LONG_PROMPT, 256, False),
    ("streaming_short", SHORT_PROMPT, 256, True),
]

for name, prompt, max_tokens, stream in tests:
    print(f"Running {name}...")
    try:
        if stream:
            result = run_stream({
                "model": model,
                "messages": [
                    {"role": "system", "content": SYSTEM},
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0.2,
                "max_tokens": max_tokens,
                "stream": True,
            }, name)
        else:
            result = run_completion(name, prompt, max_tokens=max_tokens)
        results["tests"].append(result)
        print(f"  {result['elapsed_s']}s, {result.get('tokens_per_second', 'n/a')} tok/s")
    except Exception as e:
        err = {"name": name, "error": str(e)}
        results["tests"].append(err)
        print(f"  FAILED: {e}")

print("\n=== Tool calling ===")
try:
    tool_result = run_tool_call()
    results["tests"].append(tool_result)
    status = "PASS" if tool_result["success"] else "FAIL"
    print(f"  {status}: {tool_result['detail']}")
except Exception as e:
    results["tests"].append({"name": "tool_calling", "error": str(e)})
    print(f"  FAILED: {e}")

# Summary
gen_tests = [t for t in results["tests"] if "tokens_per_second" in t]
if gen_tests:
    avg_tps = sum(t["tokens_per_second"] for t in gen_tests) / len(gen_tests)
    results["summary"] = {
        "avg_tokens_per_second": round(avg_tps, 2),
        "test_count": len(results["tests"]),
        "tool_calling_ok": any(
            t.get("name") == "tool_calling" and t.get("success") for t in results["tests"]
        ),
    }
    print(f"\n=== Summary ===")
    print(f"Average throughput: {results['summary']['avg_tokens_per_second']} tok/s")
    print(f"Tool calling: {'OK' if results['summary']['tool_calling_ok'] else 'FAILED'}")

with open(output_path, "w") as f:
    json.dump(results, f, indent=2)
    f.write("\n")

print(f"\nResults written to {output_path}")
PY

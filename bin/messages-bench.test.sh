#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
bench="$repo_dir/bin/messages-bench"
tmp="$(mktemp -d)"
failures=0
stub_pid=""
base_url=""
run_dir=""

trap 'stop_stub; rm -rf "$tmp"' EXIT

cat > "$tmp/stub.py" <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

config_path, log_path, port_path = sys.argv[1:4]
config = json.loads(Path(config_path).read_text())


def sse(kind, **fields):
    payload = dict(type=kind, **fields)
    return f"event: {kind}\ndata: {json.dumps(payload)}\n\n".encode("utf-8")


def text_events():
    yield sse("content_block_start", index=0, content_block={"type": "text", "text": ""})
    for word in ("one", "two", "three"):
        yield sse("content_block_delta", index=0, delta={"type": "text_delta", "text": word})


def tool_events():
    block = {"type": "tool_use", "id": "toolu_stub", "name": "read_file", "input": {}}
    yield sse("content_block_start", index=0, content_block=block)
    pieces = ['{"path": ', '"README.md"}']
    if config.get("bad_tool_json"):
        pieces = pieces[:1]
    for piece in pieces:
        yield sse("content_block_delta", index=0, delta={"type": "input_json_delta", "partial_json": piece})


def reply_events(body):
    usage = {
        "input_tokens": config["input_tokens"],
        "cache_read_input_tokens": config.get("cache_read_input_tokens"),
        "output_tokens": 1,
    }
    yield sse("message_start", message={"id": "msg_stub", "role": "assistant", "usage": usage})
    yield sse("ping")
    blocks = tool_events() if body.get("tools") else text_events()
    yield from blocks
    yield sse("content_block_stop", index=0)
    yield sse("message_delta", delta={"stop_reason": "end_turn"}, usage={"output_tokens": 3})
    yield sse("message_stop")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        record = {
            "anthropic-version": self.headers.get("anthropic-version"),
            "x-api-key": self.headers.get("x-api-key"),
            "body": body,
        }
        with open(log_path, "a") as log:
            log.write(json.dumps(record) + "\n")
        if self.path != "/v1/messages":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for chunk in reply_events(body):
            self.wfile.write(chunk)
            self.wfile.flush()


server = HTTPServer(("127.0.0.1", 0), Handler)
Path(port_path).write_text(str(server.server_port))
server.serve_forever()
PY

cat > "$tmp/inspect.py" <<'PY'
import json
import sys
from pathlib import Path

START_CHARS = 1000
EARLY_CHARS = 100
EXPECTED_VERSION = "2023-06-01"
PROBE_KEYS = ["prefix_tokens", "scenario", "ttft_seconds", "prefill_tokens_per_second", "decode_tokens_per_second"]


def fail(message):
    print(f"FAIL: {message}")
    sys.exit(1)


def requests_in(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines()]


def prompt(path, index):
    return requests_in(path)[index - 1]["body"]["messages"][0]["content"]


def requests_ok(path, model):
    for request in requests_in(path):
        if request["body"].get("stream") is not True:
            fail("a request was not streamed")
        if request["body"].get("model") != model:
            fail(f"a request named model {request['body'].get('model')!r}")
        if request.get("anthropic-version") != EXPECTED_VERSION:
            fail(f"anthropic-version was {request.get('anthropic-version')!r}")


def same_start(path, first, second):
    a = prompt(path, first)
    b = prompt(path, second)
    if a[:START_CHARS] != b[:START_CHARS]:
        fail("cold and warm prompts differ in the first 1000 characters")
    if a == b:
        fail("cold and warm prompts are identical")


def different_start(first_path, first, second_path, second):
    if prompt(first_path, first)[:START_CHARS] == prompt(second_path, second)[:START_CHARS]:
        fail("two runs sent the same cold prefix")


def prefixes_differ_early(path, first, second):
    if prompt(path, first)[:EARLY_CHARS] == prompt(path, second)[:EARLY_CHARS]:
        fail("two prefix sizes share their first 100 characters")


def max_tokens_is(path, index, expected):
    value = requests_in(path)[index - 1]["body"].get("max_tokens")
    if value != expected:
        fail(f"request {index} sent max_tokens {value}, expected {expected}")


def json_shape(path):
    data = json.loads(Path(path).read_text())
    if not data.get("runs"):
        fail("json output has no runs")
    for run in data["runs"]:
        missing = [key for key in PROBE_KEYS if key not in run]
        if missing:
            fail(f"run is missing {missing}")
    calls = data.get("tool_calls", {})
    if "parsed" not in calls or "trials" not in calls:
        fail("tool_calls lacks parsed or trials")


command, arguments = sys.argv[1], sys.argv[2:]
if command == "requests-ok":
    requests_ok(arguments[0], arguments[1])
elif command == "same-start":
    same_start(arguments[0], int(arguments[1]), int(arguments[2]))
elif command == "different-start":
    different_start(arguments[0], int(arguments[1]), arguments[2], int(arguments[3]))
elif command == "prefixes-differ-early":
    prefixes_differ_early(arguments[0], int(arguments[1]), int(arguments[2]))
elif command == "max-tokens":
    max_tokens_is(arguments[0], int(arguments[1]), int(arguments[2]))
elif command == "json-shape":
    json_shape(arguments[0])
PY

start_stub() {
  stop_stub
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  printf '%s' "$1" > "$run_dir/config.json"
  python3 "$tmp/stub.py" "$run_dir/config.json" "$run_dir/requests.log" "$run_dir/port" 2> "$run_dir/stub.err" &
  stub_pid=$!
  for _ in $(seq 600); do
    [ -s "$run_dir/port" ] && break
    sleep 0.05
  done
  if [ ! -s "$run_dir/port" ]; then
    echo "FAIL: bench stub did not start"
    cat "$run_dir/stub.err"
    failures=$((failures + 1))
    return 1
  fi
  base_url="http://127.0.0.1:$(cat "$run_dir/port")"
}

stop_stub() {
  if [ -n "$stub_pid" ]; then
    kill "$stub_pid" 2>/dev/null
    wait "$stub_pid" 2>/dev/null
    stub_pid=""
  fi
}

bench_run() {
  "$bench" --base-url "$base_url" "$@"
}

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

healthy='{"input_tokens": 2000, "cache_read_input_tokens": 1500, "bad_tool_json": false}'

start_stub "$healthy" || exit 1
log="$run_dir/requests.log"
if ! bench_run --model stub --prefix-tokens 2000 --tool-trials 2 > "$run_dir/stdout" 2> "$run_dir/stderr"; then
  fail "bench exits 0 against a healthy stub"
  cat "$run_dir/stderr"
fi
grep -Eq '^2000 +cold ' "$run_dir/stdout" || fail "stdout has a cold row for 2000 tokens"
grep -Eq '^2000 +warm ' "$run_dir/stdout" || fail "stdout has a warm row for 2000 tokens"
grep -qx 'tool calls: 2/2 parsed' "$run_dir/stdout" || fail "stdout reports tool calls 2/2 parsed"

if [ -s "$log" ]; then
  python3 "$tmp/inspect.py" requests-ok "$log" stub || fail "every request streams with model stub and anthropic-version 2023-06-01"
else
  fail "stub logged no requests"
fi

python3 "$tmp/inspect.py" same-start "$log" 1 2 || fail "warm request shares the cold prefix and differs in the question"
python3 "$tmp/inspect.py" max-tokens "$log" 3 2048 || fail "tool trial requests max_tokens 2048 under default flags"

start_stub "$healthy" || exit 1
bench_run --model stub --prefix-tokens 2000 3000 --tool-trials 0 > "$run_dir/stdout" 2> "$run_dir/stderr"
python3 "$tmp/inspect.py" prefixes-differ-early "$run_dir/requests.log" 1 3 || fail "cold requests for different prefix sizes differ in their first 100 characters"

start_stub "$healthy" || exit 1
bench_run --model stub --prefix-tokens 2000 --tool-trials 0 > "$run_dir/stdout" 2> "$run_dir/stderr"
python3 "$tmp/inspect.py" different-start "$log" 1 "$run_dir/requests.log" 1 || fail "two runs send different cold prefixes"

start_stub '{"input_tokens": 2000, "cache_read_input_tokens": null, "bad_tool_json": true}' || exit 1
if ! bench_run --model stub --prefix-tokens 2000 --tool-trials 2 > "$run_dir/stdout" 2> "$run_dir/stderr"; then
  fail "malformed tool JSON still exits 0"
fi
grep -qx 'tool calls: 0/2 parsed' "$run_dir/stdout" || fail "malformed tool JSON reports 0/2 parsed"

start_stub "$healthy" || exit 1
if ! bench_run --model stub --prefix-tokens 2000 --tool-trials 2 --json > "$run_dir/report.json" 2> "$run_dir/stderr"; then
  fail "--json exits 0"
fi
python3 "$tmp/inspect.py" json-shape "$run_dir/report.json" || fail "--json prints runs and tool_calls"

if "$bench" --base-url http://127.0.0.1:9 --model stub > "$tmp/unreachable.out" 2> "$tmp/unreachable.err"; then
  fail "unreachable server exits 1"
fi
grep -q 'messages-bench:' "$tmp/unreachable.err" || fail "unreachable server prints a messages-bench: error"

stop_stub

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi

#!/bin/bash
stub_llama_server="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stub-llama-server.py"
stub_llama_pid=""
stub_llama_dir=""

start_stub_llama() {
  local tries=0
  stub_llama_dir="$(mktemp -d)"
  export STUB_LLAMA_LOG="${STUB_LLAMA_LOG:-$stub_llama_dir/requests.jsonl}"
  python3 "$stub_llama_server" --port-file "$stub_llama_dir/port" --state "$1" --log "$STUB_LLAMA_LOG" &
  stub_llama_pid=$!
  while [ ! -s "$stub_llama_dir/port" ]; do
    tries=$((tries + 1))
    if [ "$tries" -gt 100 ]; then
      echo "stub-llama-lib: the stub server never wrote its port" >&2
      return 1
    fi
    sleep 0.05
  done
  LLAMA_SERVER_URL="http://127.0.0.1:$(cat "$stub_llama_dir/port")"
  export LLAMA_SERVER_URL
}

stop_stub_llama() {
  if [ -n "$stub_llama_pid" ]; then
    kill "$stub_llama_pid" 2>/dev/null
    wait "$stub_llama_pid" 2>/dev/null
  fi
  [ -z "$stub_llama_dir" ] || rm -rf "$stub_llama_dir"
  stub_llama_pid=""
  stub_llama_dir=""
  unset STUB_LLAMA_LOG
}

#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/size-profile.sh"
console_state_dir="${CLAUDE_CONSOLE_STATE_DIR:-$HOME/.local/share/claude-custom/console}"
telemetry_log="$session_config_dir/telemetry/tool-calls.jsonl"

telemetry_log_path() {
  [ "${CLAUDE_OLLAMA_TELEMETRY:-0}" = 1 ] || return 0
  printf '%s\n' "${CLAUDE_TOOL_TELEMETRY:-$telemetry_log}"
}

proxy_log_dir() {
  echo "$console_state_dir/proxy"
}

launch_beacon_file() {
  echo "$console_state_dir/beacon/$(hostname -s).json"
}

incident_watcher() {
  echo "${CLAUDE_OLLAMA_INCIDENT_WATCHER:-$profile_dir/incidents/watcher.py}"
}

run_tool_budget() {
  "${CLAUDE_OLLAMA_TOOL_BUDGET_BIN:-$repo_dir/bin/tool-budget}" \
    --proxy-log "$(proxy_log_dir)/requests.jsonl" --telemetry "${CLAUDE_TOOL_TELEMETRY:-$telemetry_log}" "$@"
}

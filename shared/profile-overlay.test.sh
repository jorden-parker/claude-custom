#!/usr/bin/env bash
set -u
script="$(cd "$(dirname "$0")" && pwd)/profile-overlay"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
base="$tmp/base.json"
mkdir -p "$tmp/profiles"
printf '%s\n' '{"permissions":{"allow":["Read","Grep"],"ask":["Edit"],"deny":["Glob","WebFetch","Agent"]},"sandbox":{"enabled":true},"env":{"KEEP":"1"}}' > "$base"

check_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1: want [$2] got [$3]"
    failures=$((failures + 1))
  fi
}

status_of() {
  "$@" >/dev/null 2>&1
  echo $?
}

settings_for() {
  printf '%s' "$2" > "$tmp/profiles/$1.json"
  "$script" settings "$base" "$tmp/profiles/$1.json" "$tmp/out-$1.json" && cat "$tmp/out-$1.json"
}

claude_out="$(settings_for claude-code '{"tools":{"Glob":"allow","Grep":"ask","Edit":"deny","WebFetch":"off","Read":"default"}}')"
check_eq "allow moves a denied tool into allow" '["Glob","Read"]' "$(printf '%s' "$claude_out" | jq -c '.permissions.allow | sort')"
check_eq "ask moves a tool out of allow into ask" '["Grep"]' "$(printf '%s' "$claude_out" | jq -c '.permissions.ask | sort')"
check_eq "deny and off both end up as a bare deny" '["Agent","Edit","WebFetch"]' "$(printf '%s' "$claude_out" | jq -c '.permissions.deny | sort')"
check_eq "default leaves the base untouched" "$(jq -c -S . "$base")" "$(settings_for claude-code '{"tools":{"Glob":"default"}}' | jq -c -S .)"
check_eq "sandbox false turns the sandbox off for claude-code" false "$(settings_for claude-code '{"sandbox":false}' | jq -r .sandbox.enabled)"
check_eq "sandbox false is ignored for an ollama profile" true "$(settings_for ollama-27b '{"sandbox":false}' | jq -r .sandbox.enabled)"
check_eq "context sets the max context tokens" 50000 "$(settings_for claude-code '{"context":50000}' | jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS')"
check_eq "context keeps the other env values" 1 "$(settings_for claude-code '{"context":50000}' | jq -r '.env.KEEP')"
check_eq "an ollama context keeps the output and summary headroom out of the max context tokens" 20480 "$(settings_for ollama-27b '{"context":32768}' | jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS')"
ollama_base="$tmp/ollama-base.json"
printf '%s\n' '{"permissions":{"allow":[],"ask":[],"deny":[]},"sandbox":{"enabled":true},"env":{"CLAUDE_CODE_MAX_CONTEXT_TOKENS":"53248","CLAUDE_CODE_MAX_OUTPUT_TOKENS":"8192"}}' > "$ollama_base"
ollama_settings_for() {
  printf '%s' "$2" > "$tmp/profiles/$1.json"
  "$script" settings "$ollama_base" "$tmp/profiles/$1.json" "$tmp/out-$1.json" && cat "$tmp/out-$1.json"
}
check_eq "output_tokens sets the max output tokens" 4096 "$(ollama_settings_for ollama-27b '{"output_tokens":4096}' | jq -r '.env.CLAUDE_CODE_MAX_OUTPUT_TOKENS')"
check_eq "output_tokens alone gives the freed tokens back to the context" 57344 "$(ollama_settings_for ollama-27b '{"output_tokens":4096}' | jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS')"
check_eq "context with output_tokens keeps the summary reserve out of the max context tokens" 24576 "$(ollama_settings_for ollama-27b '{"context":32768,"output_tokens":4096}' | jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS')"
check_eq "output_tokens is ignored for claude-code" 8192 "$(ollama_settings_for claude-code '{"output_tokens":4096}' | jq -r '.env.CLAUDE_CODE_MAX_OUTPUT_TOKENS')"
check_eq "an ollama context below the headroom is refused" 1 "$(printf '%s' '{"context":8192}' > "$tmp/profiles/ollama-27b.json"; status_of "$script" settings "$base" "$tmp/profiles/ollama-27b.json" "$tmp/out.json")"
printf '%s\n' '{"env":{"KEEP":"1","CLAUDE_CODE_EXTRA_BODY":"{\"thinking\":{\"type\":\"disabled\"}}"}}' > "$tmp/thinking-base.json"
thinking_for() {
  printf '%s' "$2" > "$tmp/profiles/$1.json"
  "$script" settings "$tmp/thinking-base.json" "$tmp/profiles/$1.json" "$tmp/out-thinking-$1.json" && jq -r '.env.CLAUDE_CODE_EXTRA_BODY // "absent"' "$tmp/out-thinking-$1.json"
}
check_eq "thinking true drops the extra body that turns thinking off" absent "$(thinking_for ollama-27b '{"thinking":true}')"
check_eq "thinking false keeps it" '{"thinking":{"type":"disabled"}}' "$(thinking_for ollama-27b '{"thinking":false}')"
check_eq "thinking true keeps the other env values" 1 "$(jq -r .env.KEEP "$tmp/out-thinking-ollama-27b.json")"
check_eq "thinking is ignored for claude-code" '{"thinking":{"type":"disabled"}}' "$(thinking_for claude-code '{"thinking":true}')"
check_eq "an ollama profile cannot allow Agent" true "$(settings_for ollama-27b '{"tools":{"Agent":"allow"}}' | jq -r '.permissions.deny | index("Agent") != null')"
check_eq "an ollama profile can allow Glob" '["Glob"]' "$(settings_for ollama-27b '{"tools":{"Glob":"allow"}}' | jq -c '.permissions.allow | map(select(. == "Glob"))')"
check_eq "a missing profile passes the base through" "$(jq -c -S . "$base")" "$("$script" settings "$base" "$tmp/profiles/absent.json" "$tmp/out-absent.json" && jq -c -S . "$tmp/out-absent.json")"
check_eq "the settings file is written 0600" yes "$([ -n "$(find "$tmp/out-claude-code.json" -perm 600)" ] && echo yes)"
mkdir -p "$tmp/linked"
ln -s "$tmp/profiles/claude-code.json" "$tmp/linked/claude-code.json"
check_eq "a symlinked settings profile is refused" 1 "$(status_of "$script" settings "$base" "$tmp/linked/claude-code.json" "$tmp/out-linked.json")"
printf '[1]' > "$tmp/profiles/bad.json"
check_eq "a profile that is not an object is refused" 1 "$(status_of "$script" settings "$base" "$tmp/profiles/bad.json" "$tmp/out-bad.json")"

tools_profile="$tmp/profiles/ollama-27b.json"
printf '%s' '{"tools":{"Glob":"allow","Edit":"off","Write":"deny","Agent":"allow","WebFetch":"ask","Skill":"default"}}' > "$tools_profile"
check_eq "tools allow and ask add, off and deny remove, Agent is never added" "Bash,Read,Skill,TaskStop,Glob,WebFetch" "$("$script" tools "Bash,Read,Edit,Write,Skill,TaskStop" "$tools_profile")"
check_eq "tools without a profile prints the base list" "Bash,Read,Edit" "$("$script" tools "Bash,Read,Edit" "$tmp/profiles/absent.json")"
printf '%s' '{"tools":{"Read":"allow"}}' > "$tmp/profiles/read.json"
check_eq "tools does not repeat a tool already listed" "Bash,Read,Edit" "$("$script" tools "Bash,Read,Edit" "$tmp/profiles/read.json")"

printf '%s' '{"env":{"CLAUDE_OLLAMA_TELEMETRY":"0","CLAUDE_OLLAMA_NO_INDEX":1,"NOT_ALLOWED":"x"}}' > "$tmp/profiles/env.json"
env_out="$(env -u CLAUDE_OLLAMA_TELEMETRY -u CLAUDE_OLLAMA_NO_INDEX "$script" env "$tmp/profiles/env.json")"
check_eq "env exports an allowlisted key" "export CLAUDE_OLLAMA_TELEMETRY='0'" "$(printf '%s\n' "$env_out" | grep CLAUDE_OLLAMA_TELEMETRY)"
check_eq "env exports a numeric value as a string" "export CLAUDE_OLLAMA_NO_INDEX='1'" "$(printf '%s\n' "$env_out" | grep CLAUDE_OLLAMA_NO_INDEX)"
check_eq "env skips keys outside the allowlist" "" "$(printf '%s\n' "$env_out" | grep NOT_ALLOWED)"
check_eq "a variable already set in the environment wins" "" "$(CLAUDE_OLLAMA_TELEMETRY=1 "$script" env "$tmp/profiles/env.json" | grep CLAUDE_OLLAMA_TELEMETRY)"
printf '%s' '{"env":{"CLAUDE_OLLAMA_HANDOFF_PCT":"60","CLAUDE_OLLAMA_RELAUNCH":"0","CLAUDE_OLLAMA_INCIDENTS":"0","HANDOFF_UNKNOWN":"1"}}' > "$tmp/profiles/handoff.json"
handoff_out="$(env -u CLAUDE_OLLAMA_HANDOFF_PCT -u CLAUDE_OLLAMA_RELAUNCH -u CLAUDE_OLLAMA_INCIDENTS "$script" env "$tmp/profiles/handoff.json")"
check_eq "env exports the handoff threshold" "export CLAUDE_OLLAMA_HANDOFF_PCT='60'" "$(printf '%s\n' "$handoff_out" | grep CLAUDE_OLLAMA_HANDOFF_PCT)"
check_eq "env exports the relaunch and incident switches" "export CLAUDE_OLLAMA_RELAUNCH='0'
export CLAUDE_OLLAMA_INCIDENTS='0'" "$(printf '%s\n' "$handoff_out" | grep -E 'RELAUNCH|INCIDENTS')"
check_eq "env still drops a key outside the allowlist" "" "$(printf '%s\n' "$handoff_out" | grep HANDOFF_UNKNOWN)"
printf '%s' '{"env":{"CLAUDE_OLLAMA_PROXY":"0","CLAUDE_OLLAMA_PROXY_RECORD":"1","CLAUDE_OLLAMA_PROXY_STABILIZE":"1","CLAUDE_CUSTOM_FRICTION":"0","CLAUDE_OLLAMA_LEASE":"0","CLAUDE_OLLAMA_LEASE_HEARTBEAT":"60","CLAUDE_OLLAMA_LADDER":"0","CLAUDE_OLLAMA_FIT":"0","CLAUDE_OLLAMA_BEACON":"0","CLAUDE_OLLAMA_RULE_CARDS":"0","CLAUDE_OLLAMA_TEST_AFTER_EDIT":"run","CLAUDE_OLLAMA_EDIT_NUDGE":"0","CLAUDE_OLLAMA_PROXY_BIN":"/tmp/x"}}' > "$tmp/profiles/switches.json"
switches_out="$(env -u CLAUDE_OLLAMA_PROXY -u CLAUDE_OLLAMA_PROXY_RECORD -u CLAUDE_OLLAMA_PROXY_STABILIZE -u CLAUDE_CUSTOM_FRICTION -u CLAUDE_OLLAMA_LEASE -u CLAUDE_OLLAMA_LEASE_HEARTBEAT -u CLAUDE_OLLAMA_LADDER -u CLAUDE_OLLAMA_FIT -u CLAUDE_OLLAMA_BEACON -u CLAUDE_OLLAMA_RULE_CARDS -u CLAUDE_OLLAMA_TEST_AFTER_EDIT -u CLAUDE_OLLAMA_EDIT_NUDGE "$script" env "$tmp/profiles/switches.json")"
check_eq "env exports every harness switch" "export CLAUDE_CUSTOM_FRICTION='0'
export CLAUDE_OLLAMA_BEACON='0'
export CLAUDE_OLLAMA_EDIT_NUDGE='0'
export CLAUDE_OLLAMA_FIT='0'
export CLAUDE_OLLAMA_LADDER='0'
export CLAUDE_OLLAMA_LEASE='0'
export CLAUDE_OLLAMA_LEASE_HEARTBEAT='60'
export CLAUDE_OLLAMA_PROXY='0'
export CLAUDE_OLLAMA_PROXY_RECORD='1'
export CLAUDE_OLLAMA_PROXY_STABILIZE='1'
export CLAUDE_OLLAMA_RULE_CARDS='0'
export CLAUDE_OLLAMA_TEST_AFTER_EDIT='run'" "$(printf '%s\n' "$switches_out" | sort)"
check_eq "env never exports a script override" "" "$(printf '%s\n' "$switches_out" | grep PROXY_BIN)"
payload="x'; touch $tmp/pwned; '"
jq -n --arg value "$payload" '{env: {CLAUDE_OLLAMA_CMUX: $value}}' > "$tmp/profiles/hostile.json"
check_eq "a hostile value reaches the variable unchanged" "$payload" "$(env -u CLAUDE_OLLAMA_CMUX sh -c "eval \"\$(\"\$1\" env \"\$2\")\"; printf '%s' \"\$CLAUDE_OLLAMA_CMUX\"" _ "$script" "$tmp/profiles/hostile.json")"
check_eq "and a hostile value runs nothing" missing "$([ -e "$tmp/pwned" ] && echo present || echo missing)"

printf '%s' '{"mcp":{"dev":false}}' > "$tmp/profiles/mcp.json"
check_eq "a disabled MCP server reports false" false "$("$script" mcp "$tmp/profiles/mcp.json" dev)"
check_eq "an MCP server not named stays enabled" true "$("$script" mcp "$tmp/profiles/mcp.json" repo)"
check_eq "without a profile every MCP server stays enabled" true "$("$script" mcp "$tmp/profiles/absent.json" dev)"

printf '%s' '{"context":32768,"parameters":{"temperature":0.6,"min_p":0.05}}' > "$tmp/profiles/params.json"
check_eq "parameters merge over the Modelfile values and add new keys" "num_ctx 32768
temperature 0.6
top_k 20
min_p 0.05" "$(printf 'num_ctx 65536\ntemperature 0.7\ntop_k 20\n' | "$script" parameters "$tmp/profiles/params.json")"
printf '%s' '{"output_tokens":4096}' > "$tmp/profiles/output.json"
check_eq "output_tokens replaces the Modelfile num_predict" "num_ctx 65536
num_predict 4096" "$(printf 'num_ctx 65536\nnum_predict 8192\n' | "$script" parameters "$tmp/profiles/output.json")"
check_eq "parameters without a profile keep the Modelfile values" "num_ctx 65536" "$(printf 'num_ctx 65536\n' | "$script" parameters "$tmp/profiles/absent.json")"

xdg="$tmp/xdg"
mkdir -p "$xdg/claude-custom/profiles"
check_eq "sandbox-off is false with no machine files" false "$(XDG_CONFIG_HOME="$xdg" "$script" sandbox-off)"
printf '%s' '{"sandbox":false}' > "$xdg/claude-custom/profiles/claude-code.json"
check_eq "sandbox-off is true when claude-code turns the sandbox off" true "$(XDG_CONFIG_HOME="$xdg" "$script" sandbox-off)"
printf '%s' '{"sandbox":true}' > "$xdg/claude-custom/profiles/claude-code.json"
check_eq "sandbox-off is false when claude-code keeps the sandbox on" false "$(XDG_CONFIG_HOME="$xdg" "$script" sandbox-off)"
touch "$xdg/claude-custom/sandbox-off"
check_eq "sandbox-off is true when the sandbox-off file exists" true "$(XDG_CONFIG_HOME="$xdg" "$script" sandbox-off)"
rm -f "$xdg/claude-custom/sandbox-off"

printf '%s' '{"tools":{"Glob":"allow"},"thinking":true,"output_tokens":4096,"mcp":{"dev":false}}' > "$tmp/profiles/summary.json"
check_eq "summary lists the overrides in effect" "tools.Glob=allow, thinking=true, output_tokens=4096, mcp.dev=false" "$("$script" summary "$tmp/profiles/summary.json")"
check_eq "summary says none without a profile" none "$("$script" summary "$tmp/profiles/absent.json")"

check_eq "check accepts a missing profile" 0 "$(status_of "$script" check "$tmp/profiles/absent.json")"
check_eq "check accepts a valid profile" 0 "$(status_of "$script" check "$tmp/profiles/summary.json")"
check_eq "check refuses a symlinked profile" 1 "$(status_of "$script" check "$tmp/linked/claude-code.json")"
check_eq "check refuses a profile that is not an object" 1 "$(status_of "$script" check "$tmp/profiles/bad.json")"
check_eq "no subcommand is a usage error" 2 "$(status_of "$script")"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi

#!/usr/bin/env bash
set -u
source_repo="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
failures=0
repo="$tmp/repo"
config="$tmp/xdg/claude-custom"
cache="$tmp/cache/claude-custom/settings.tokens.json"
jq_dir="$(dirname "$(command -v jq)")"

check_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1: want [$2] got [$3]"
    failures=$((failures + 1))
  fi
}

mkdir -p "$repo/personal" "$repo/shared" "$tmp/home" "$tmp/bin"
cp "$source_repo/personal/settings-path" "$source_repo/personal/launch" \
  "$source_repo/personal/settings.tokens.json" "$repo/personal/"
cp "$source_repo/shared/profile-overlay" "$source_repo/shared/sandbox-env" "$repo/shared/"
cat > "$tmp/bin/claude" <<'EOF'
#!/bin/sh
echo "ARGS: $*"
echo "SANDBOX_CACHE=${CLAUDE_SANDBOX_CACHE_DIR-unset}"
EOF
chmod +x "$repo/personal/settings-path" "$repo/personal/launch" "$repo/shared/profile-overlay" "$repo/shared/sandbox-env" "$tmp/bin/claude"

run_in_config() {
  env -i HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" XDG_CACHE_HOME="$tmp/cache" PATH="$tmp/bin:$jq_dir:/usr/bin:/bin" "$@"
}

settings_path() {
  run_in_config "$repo/personal/settings-path" 2>/dev/null
}

shared_overlay="$repo/personal/settings.tokens.json"
check_eq "without any local file the shared overlay is used" "$shared_overlay" "$(settings_path)"

mkdir -p "$config"
printf 'WebFetch\n' > "$config/enabled-tools"
check_eq "enabled-tools alone lifts the bare deny" "$cache" "$(settings_path)"
check_eq "enabled-tools removes WebFetch from deny" true "$(jq '.permissions.deny | index("WebFetch") == null' "$cache")"
rm -f "$config/enabled-tools"

mkdir -p "$config/profiles"
printf '%s' '{"tools":{"WebFetch":"deny"}}' > "$config/profiles/claude-code.json"
check_eq "a claude-code profile is layered after enabled-tools" "$cache" "$(settings_path)"
check_eq "the profile puts WebFetch back in deny" true "$(jq '.permissions.deny | index("WebFetch") != null' "$cache")"
rm -f "$config/profiles/claude-code.json"

printf '%s' '{"sandbox":false,"tools":{"WebFetch":"allow"},"context":50000}' > "$config/profiles/claude-code.json"
check_eq "a profile alone selects the derived overlay" "$cache" "$(settings_path)"
check_eq "the profile turns the sandbox off in the derived overlay" false "$(jq '.sandbox.enabled' "$cache")"
check_eq "the profile sets the context tokens in the derived overlay" 50000 "$(jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS' "$cache")"
check_eq "the profile allows a tool in the derived overlay" true "$(jq '.permissions.allow | index("WebFetch") != null' "$cache")"

rm -f "$config/profiles/claude-code.json"
printf '%s' '{"sandbox":false,"tools":{"WebFetch":"allow"}}' > "$config/profiles/ollama-27b.json"
check_eq "an ollama profile never selects the claude-code overlay" "$shared_overlay" "$(settings_path)"
rm -f "$config/profiles/ollama-27b.json"

rm -f "$config/profiles/claude-code.json"
check_eq "launch passes the shared overlay without a profile" "ARGS: --settings $shared_overlay -p hi" "$(run_in_config "$repo/personal/launch" -p hi 2>/dev/null | head -n 1)"
check_eq "launch runs claude in the sandbox env when no profile turns it off" "SANDBOX_CACHE=$tmp/home/.cache/claude-sandbox" "$(run_in_config "$repo/personal/launch" -p hi 2>/dev/null | tail -n 1)"

printf '%s' '{"sandbox":false}' > "$config/profiles/claude-code.json"
check_eq "launch passes the derived overlay when a profile turns the sandbox off" "ARGS: --settings $cache -p hi" "$(run_in_config "$repo/personal/launch" -p hi 2>/dev/null | head -n 1)"
check_eq "that overlay has the sandbox off" false "$(jq '.sandbox.enabled' "$cache")"
check_eq "a profile with sandbox false runs claude without sandbox-env" "SANDBOX_CACHE=unset" "$(run_in_config "$repo/personal/launch" -p hi 2>/dev/null | tail -n 1)"
rm -f "$config/profiles/claude-code.json"

printf '' > "$config/sandbox-off"
check_eq "the sandbox-off file runs claude without sandbox-env" "SANDBOX_CACHE=unset" "$(run_in_config "$repo/personal/launch" -p hi 2>/dev/null | tail -n 1)"
rm -f "$config/sandbox-off"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi

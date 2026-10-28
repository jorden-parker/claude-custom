#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
probe="$repo_dir/bin/sandbox-probe"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/spt.XXXXXX")"
failures=0
stub_dir="$tmp/stub"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$stub_dir" "$tmp/home/.config/claude-custom"
cat > "$stub_dir/srt" <<'SH'
#!/usr/bin/env bash
printf 'args: %s\npwd: %s\n' "$*" "$(pwd)" >> "$STUB_SRT_LOG"
while [ $# -gt 0 ]; do
  if [ "$1" = -s ]; then
    cp "$2" "$STUB_SRT_LOG.policy"
  fi
  shift
done
if [ -n "${STUB_SRT_STDOUT:-}" ]; then
  printf '%s' "$STUB_SRT_STDOUT"
fi
exit "${STUB_SRT_EXIT:-0}"
SH
chmod +x "$stub_dir/srt"

sandbox_exec_present=0
if [ -x /usr/bin/sandbox-exec ]; then
  sandbox_exec_present=1
fi

expect_true() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok: $label"
  else
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

contains_line() {
  printf '%s\n' "$1" | grep -Fq -- "$2"
}

matches_line() {
  printf '%s\n' "$1" | grep -Eq -- "$2"
}

run_probe() {
  rm -f "$tmp/log" "$tmp/log.policy"
  SANDBOX_PROBE_SRT="$stub_dir/srt" STUB_SRT_LOG="$tmp/log" HOME="$tmp/home" "$probe" "$@" 2>&1
}

policy_matches_repo_network() {
  [ "$(jq -c .network "$tmp/log.policy")" = "$(jq -c .network "$repo_dir/ollama/sandbox.json")" ]
}

policy_has_secret_env() {
  [ "$(jq -r '.credentials.envVars[0].name' "$tmp/log.policy")" = "PROBE_SECRET" ]
}

secret_absent_from_argv_and_policy() {
  ! grep -Eq '[0-9a-f]{32}' "$tmp/log" "$tmp/log.policy"
}

policy_has_both_deny_keys() {
  jq -e '.filesystem | has("denyRead") and has("denyReads")' "$tmp/log.policy" >/dev/null
}

ran_from_project() {
  grep -Eq 'pwd: .*/project$' "$tmp/log"
}

test_missing_srt_exits_one() {
  local out status
  out="$(env -u SANDBOX_PROBE_SRT HOME="$tmp/empty-home" "$probe" 2>&1)"
  status=$?
  [ "$status" -eq 1 ] && contains_line "$out" "sandbox-probe: sandbox-runtime is missing; run claude-custom install"
}

test_nested_seatbelt_ok() {
  local out status want
  out="$(STUB_SRT_EXIT=0 run_probe --only nested_seatbelt)"
  status=$?
  want="ok: a second Seatbelt sandbox starts inside srt (nested sandbox works)"
  if [ "$sandbox_exec_present" -eq 0 ]; then
    want="skip: sandbox-exec is missing from /usr/bin"
  fi
  [ "$status" -eq 0 ] && contains_line "$out" "$want"
}

test_nested_seatbelt_refused() {
  local out status
  out="$(STUB_SRT_EXIT=1 run_probe --only nested_seatbelt)"
  status=$?
  if [ "$sandbox_exec_present" -eq 0 ]; then
    [ "$status" -eq 0 ] && contains_line "$out" "skip: sandbox-exec is missing from /usr/bin"
    return
  fi
  [ "$status" -eq 1 ] && contains_line "$out" "FAIL: a second Seatbelt sandbox is refused inside srt (exit 1): "
}

test_summary_line_form() {
  local out
  out="$(STUB_SRT_EXIT=0 run_probe --only nested_seatbelt)"
  matches_line "$out" '^sandbox-probe: [0-9]+ checks, [0-9]+ failed$'
}

test_api_host_policy_matches_repo() {
  STUB_SRT_EXIT=0 run_probe --only api_host_match >/dev/null
  policy_matches_repo_network && grep -q 'https://github.com/' "$tmp/log"
}

test_body_injection_policy_hides_secret() {
  STUB_SRT_EXIT=0 run_probe --only body_injection >/dev/null
  policy_has_secret_env && secret_absent_from_argv_and_policy
}

test_unknown_policy_key_policy_has_both_keys() {
  STUB_SRT_EXIT=0 run_probe --only unknown_policy_key >/dev/null
  policy_has_both_deny_keys
}

test_rule_file_runs_from_project() {
  STUB_SRT_EXIT=0 run_probe --only rule_file_protected >/dev/null
  ran_from_project
}

test_pasteboard_needs_clipboard_flag() {
  local out
  out="$(STUB_SRT_EXIT=0 run_probe --only pasteboard)"
  contains_line "$out" "skip: pasteboard check needs --clipboard"
}

test_unknown_check_is_usage_error() {
  local out status
  out="$(run_probe --only nonsense)"
  status=$?
  [ "$status" -eq 2 ] && contains_line "$out" "sandbox-probe: unknown check nonsense; checks: nested_seatbelt api_host_match body_injection unknown_policy_key rule_file_protected gh_https_proxy pasteboard"
}

expect_true "missing srt exits 1 with the install hint" test_missing_srt_exits_one
expect_true "nested Seatbelt reports ok when srt exits 0" test_nested_seatbelt_ok
expect_true "nested Seatbelt reports FAIL when srt refuses it" test_nested_seatbelt_refused
expect_true "summary line has the N checks, M failed form" test_summary_line_form
expect_true "api host check passes the repo network policy" test_api_host_policy_matches_repo
expect_true "body injection passes PROBE_SECRET and never the value" test_body_injection_policy_hides_secret
expect_true "unknown policy key check passes denyRead and denyReads" test_unknown_policy_key_policy_has_both_keys
expect_true "rule file check runs srt from the project folder" test_rule_file_runs_from_project
expect_true "pasteboard check is skipped without --clipboard" test_pasteboard_needs_clipboard_flag
expect_true "unknown check exits 2 with the list of checks" test_unknown_check_is_usage_error

if [ "$failures" -gt 0 ]; then
  echo "sandbox-probe.test.sh: $failures failed"
  exit 1
fi
echo "all passed"

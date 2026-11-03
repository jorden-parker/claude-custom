#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
listing="$repo/bin/skill-listing"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

write_skill() {
  mkdir -p "$1/$2"
  printf '%s\n' "$3" > "$1/$2/SKILL.md"
}

first="$sandbox/first"
second="$sandbox/second"
write_skill "$first" plain $'---\nname: plain\ndescription: Short line.\n---\nbody'
write_skill "$first" folded $'---\nname: folded\ndescription: >\n  Two folded\n  lines.\nwhen_to_use: When asked.\n---\nbody'
write_skill "$first" quoted $'---\ndescription: "Quoted: text"\n---\nbody'
write_skill "$first" hidden $'---\nname: hidden\ndescription: Never listed.\ndisable-model-invocation: true\n---\nbody'
write_skill "$second" plain $'---\nname: plain\ndescription: A much longer line that the first folder overrides.\n---\nbody'
write_skill "$second" extra $'---\nname: extra\ndescription: Extra.\n---\nbody'

entries="$("$listing" --entries "$first" "$second")"
expected='- extra: Extra.
- folded: Two folded lines. - When asked.
- plain: Short line.
- quoted: Quoted: text'
check "--entries prints one line per listed skill, first folder winning, hidden skills left out" \
  test "$entries" = "$expected"

total=$(printf '%s' "$expected" | wc -c | tr -d ' ')
check "the listing fits a budget of context x 4 x fraction" \
  "$listing" --context 1000 --fraction 0.05 "$first" "$second" >/dev/null
fits_line="$("$listing" --context 1000 --fraction 0.05 "$first" "$second")"
check "a fitting listing says so with its size and the budget" \
  test "$fits_line" = "fits: $total of 200 chars, 4 skills"

over_line="$("$listing" --context 100 --fraction 0.05 "$first" "$second")"
over_status=$?
check "an oversized listing exits 1" test "$over_status" -eq 1
check "an oversized listing names the size, the budget and the remedy" \
  test "$over_line" = "over: $total of 20 chars, 4 skills; some reach the model as a bare name"

long="$sandbox/long"
write_skill "$long" big "---
name: big
description: $(printf 'x%.0s' $(seq 1 2000))
---
body"
long_entry="$("$listing" --entries "$long")"
check "a description is cut to 1536 chars with an ellipsis, like Claude Code's listing" \
  test "$long_entry" = "- big: $(printf 'x%.0s' $(seq 1 1535))…"

check "a missing folder is skipped" "$listing" --entries "$sandbox/nowhere" "$first" >/dev/null

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi

#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$repo/bin/ollama-models"
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

sha_of() {
  printf '%s' "$1" | shasum -a 256 | cut -c1-64
}

mkdir -p "$sandbox/stubbin" "$sandbox/profile" "$sandbox/weights" "$sandbox/hf"
export CLAUDE_OLLAMA_PROFILE_DIR="$sandbox/profile"
export CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/weights"
export CLAUDE_OLLAMA_SHA_CACHE="$sandbox/cache/weights-sha256.tsv"
export HF_ENDPOINT="https://hf.test"
export CLAUDE_OLLAMA_PROFILES_BIN="$sandbox/stubbin/ollama-profiles"
export PATH="$sandbox/stubbin:$PATH"

cat >"$sandbox/profile/sizes.json" <<'EOF'
{
  "27b": {
    "base": "org/Big-GGUF/big.gguf",
    "model": "big-cc",
    "context": 65536,
    "gguf": { "repo": "org/Big-GGUF", "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "file": "big.gguf" }
  },
  "35b": {
    "base": "org/Wide-GGUF/wide.gguf",
    "model": "wide-cc",
    "context": 98304,
    "gguf": { "repo": "org/Wide-GGUF", "revision": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "file": "wide.gguf" }
  }
}
EOF
cat >"$sandbox/profile/embedding.json" <<'EOF'
{
  "model": "embed:0.6b",
  "context": 8192,
  "gguf": { "repo": "org/Embed-GGUF", "revision": "cccccccccccccccccccccccccccccccccccccccc", "file": "embed.gguf" }
}
EOF
cat >"$sandbox/profile/model-digests.json" <<EOF
{
  "org/Big-GGUF/big.gguf": "$(sha_of big-weights)",
  "org/Wide-GGUF/wide.gguf": "$(sha_of wide-weights)",
  "org/Embed-GGUF/embed.gguf": "$(sha_of embed-weights)"
}
EOF

printf 'big-weights' >"$sandbox/weights/big.gguf"
printf 'tampered' >"$sandbox/weights/wide.gguf"
printf 'embed-weights' >"$sandbox/weights/embed.gguf"
printf 'old' >"$sandbox/weights/retired.gguf"
printf 'half' >"$sandbox/weights/big.gguf.part"
printf 'next' >"$sandbox/weights/big.gguf.next"

cat >"$sandbox/stubbin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/curl.log"
case "\$*" in
  *hf.test/api/models/org/Big-GGUF/revision/main*) printf '{"id":"org/Big-GGUF","sha":"dddddddddddddddddddddddddddddddddddddddd"}' ;;
  *hf.test/api/models/org/Wide-GGUF/revision/main*) printf '{"id":"org/Wide-GGUF","sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}' ;;
  *hf.test/api/models/org/Embed-GGUF/revision/main*) printf '{"id":"org/Embed-GGUF","sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}' ;;
  *hf.test/api/models/org/Big-GGUF/tree/dddddddddddddddddddddddddddddddddddddddd*) printf '[{"type":"file","path":"README.md"},{"type":"file","path":"big.gguf","lfs":{"oid":"$(sha_of new-big)","size":7}}]' ;;
  *hf.test/api/models/org/Big-GGUF/tree/ffffffffffffffffffffffffffffffffffffffff*) printf '[{"type":"file","path":"big.gguf","lfs":{"oid":"$(sha_of pinned-big)","size":10}}]' ;;
  *hf.test/api/models/org/Embed-GGUF/tree/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee*) printf '[{"type":"file","path":"embed.gguf","lfs":{"oid":"$(sha_of new-embed)","size":9}}]' ;;
  *hf.test/api/models/org/Wide-GGUF/tree/*) printf '[{"type":"file","path":"README.md"}]' ;;
  *) exit 22 ;;
esac
EOF
cat >"$sandbox/stubbin/ollama-profiles" <<EOF
#!/bin/sh
echo rendered >> "$sandbox/profiles.log"
EOF
chmod +x "$sandbox/stubbin/curl" "$sandbox/stubbin/ollama-profiles"

listing="$("$script" list)"
check "list marks a size's weights that match their pin" grep -Eq '^pinned +big.gguf$' <<<"$listing"
check "list marks the embedding weights that match their pin" grep -Eq '^pinned +embed.gguf$' <<<"$listing"
check "list marks weights that miss their pin" grep -Eq '^mismatch +wide.gguf$' <<<"$listing"
check "list marks a GGUF no pin names as an orphan" grep -Eq '^orphan +retired.gguf$' <<<"$listing"
check "list marks an unfinished download as partial" grep -Eq '^partial +big.gguf.part$' <<<"$listing"
check "list marks an upgrade candidate" grep -Eq '^candidate +big.gguf.next$' <<<"$listing"
check "list prints one line per file" test "$(wc -l <<<"$listing" | tr -d ' ')" = 6
check "list caches each file's sha256" test "$(wc -l <"$CLAUDE_OLLAMA_SHA_CACHE" | tr -d ' ')" = 3

printf 'xxxxxxxxxxx' >"$sandbox/weights/big.gguf"
touch -t 202001010000 "$sandbox/weights/big.gguf"
check "a changed file is hashed again" grep -Eq '^mismatch +big.gguf$' <<<"$("$script" list)"
printf 'big-weights' >"$sandbox/weights/big.gguf"

check "an empty weights folder lists nothing" test -z "$(CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/none" "$script" list)"

"$script" prune </dev/null >"$sandbox/out" 2>&1
check "prune with no answer refuses" test "$?" = 1
check "prune without confirmation removes nothing" test -f "$sandbox/weights/retired.gguf"

printf 'n\n' | "$script" prune >"$sandbox/out" 2>&1
check "prune declined removes nothing" test -f "$sandbox/weights/big.gguf.part"

printf 'y\n' | "$script" prune >"$sandbox/out" 2>&1
check "prune confirmed exits 0" test "$?" = 0
check "prune lists what it removes" test "$(cat "$sandbox/out")" = "$(printf 'big.gguf.part\nretired.gguf\nRemove these files? [y/N] ')"
check "prune removes the orphan" test ! -e "$sandbox/weights/retired.gguf"
check "prune removes the partial download" test ! -e "$sandbox/weights/big.gguf.part"
check "prune keeps pinned, mismatched and candidate files" test -f "$sandbox/weights/big.gguf" -a -f "$sandbox/weights/wide.gguf" -a -f "$sandbox/weights/big.gguf.next"

check "prune with nothing to remove says so" test "$("$script" prune --yes)" = "nothing to prune"

printf 'old' >"$sandbox/weights/retired.gguf"
printf 'old' >"$sandbox/weights/older.gguf"
"$script" prune --yes --only retired.gguf big.gguf >"$sandbox/out" 2>&1
check "prune --only skips a file that is not prunable" grep -Fxq 'skipped big.gguf (not prunable)' "$sandbox/out"
check "prune --only removes the named prunable file" test ! -e "$sandbox/weights/retired.gguf"
check "prune --only keeps the prunable files it was not given" test -f "$sandbox/weights/older.gguf"
check "prune --only never removes a skipped file" test -f "$sandbox/weights/big.gguf"

check "prune --only with no prunable name says so" test "$("$script" prune --yes --only big.gguf | tail -n 1)" = "nothing to prune"
check "prune --only refuses a path" test "$("$script" prune --yes --only ../profile/sizes.json | head -n 1)" = "skipped ../profile/sizes.json (not prunable)"
"$script" prune --only older.gguf >/dev/null 2>&1 </dev/null
check "prune --only without --yes is a usage error" test "$?" = 2
"$script" prune --yes --only >/dev/null 2>&1
check "prune --yes --only with no names is a usage error" test "$?" = 2
check "an unknown command is a usage error" test "$("$script" frobnicate 2>/dev/null; echo $?)" = 2

outdated_listing="$("$script" outdated 2>&1)"
outdated_status=$?
line_after() {
  grep -A1 -E "$1" <<<"$outdated_listing" | tail -n 1
}
check "outdated marks a size whose repo moved on as behind" grep -Fxq 'behind   27b (aaaaaaaaaaaa → dddddddddddd)' <<<"$outdated_listing"
check "a behind size is followed by the model-upgrade fix" test "$(line_after '^behind +27b ')" = '     fix: bin/model-upgrade 27b'
check "outdated marks a size at the repo's main as current" grep -Fxq 'current  35b' <<<"$outdated_listing"
check "outdated checks the embedding weights" grep -Fxq 'behind   embedding (cccccccccccc → eeeeeeeeeeee)' <<<"$outdated_listing"
check "the behind embedding is followed by the pin fix" test "$(line_after '^behind +embedding ')" = '     fix: bin/ollama-models pin embedding'
check "outdated ends with a count of what needs a fix" grep -Fxq '2 behind: run the fix lines above, then commit ollama/sizes.json and ollama/model-digests.json' <<<"$outdated_listing"
check "outdated exits 1 when one is behind" test "$outdated_status" = 1
check "outdated asks the Hugging Face API for main" grep -q 'https://hf.test/api/models/org/Big-GGUF/revision/main' "$sandbox/curl.log"
check "outdated NAME checks only that size" test "$("$script" outdated 35b 2>&1)" = 'current  35b'
check "outdated NAME exits 0 when it is current" test "$("$script" outdated 35b >/dev/null 2>&1; echo $?)" = 0
check "outdated NAME exits 1 when it is behind" test "$("$script" outdated 27b >/dev/null 2>&1; echo $?)" = 1
check "outdated names a size it does not know" grep -Fxq 'unknown  9b (not a size in ollama/sizes.json)' <<<"$("$script" outdated 9b 2>&1)"
check "outdated exits 1 for a size it does not know" test "$("$script" outdated 9b >/dev/null 2>&1; echo $?)" = 1
check "outdated says when the API has no answer" grep -Fxq 'unknown  27b (no revision at https://hf.none)' <<<"$(HF_ENDPOINT=https://hf.none "$script" outdated 27b 2>&1)"
check "an unanswered API is no failure" test "$(HF_ENDPOINT=https://hf.none "$script" outdated 27b >/dev/null 2>&1; echo $?)" = 0

pin_listing="$("$script" pin 27b)"
check "pin writes the repo's main revision into sizes.json" test "$(jq -r '.["27b"].gguf.revision' "$sandbox/profile/sizes.json")" = dddddddddddddddddddddddddddddddddddddddd
check "pin writes the LFS sha256 into model-digests.json" test "$(jq -r '.["org/Big-GGUF/big.gguf"]' "$sandbox/profile/model-digests.json")" = "$(sha_of new-big)"
check "pin keeps the other pins" test "$(jq -r '.["org/Wide-GGUF/wide.gguf"]' "$sandbox/profile/model-digests.json")" = "$(sha_of wide-weights)"
check "pin keeps the other sizes" test "$(jq -r '.["35b"].gguf.revision' "$sandbox/profile/sizes.json")" = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
check "pin renders the profiles" test "$(cat "$sandbox/profiles.log")" = rendered
check "pin prints the size, revision and sha256" test "$pin_listing" = "27b dddddddddddddddddddddddddddddddddddddddd $(sha_of new-big)"

"$script" pin 27b --revision ffffffffffffffffffffffffffffffffffffffff >/dev/null
check "pin --revision pins that revision" test "$(jq -r '.["27b"].gguf.revision' "$sandbox/profile/sizes.json")" = ffffffffffffffffffffffffffffffffffffffff
check "pin --revision reads that revision's sha256" test "$(jq -r '.["org/Big-GGUF/big.gguf"]' "$sandbox/profile/model-digests.json")" = "$(sha_of pinned-big)"

"$script" pin embedding >/dev/null
check "pin embedding writes embedding.json" test "$(jq -r .gguf.revision "$sandbox/profile/embedding.json")" = eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
check "pin embedding writes its sha256" test "$(jq -r '.["org/Embed-GGUF/embed.gguf"]' "$sandbox/profile/model-digests.json")" = "$(sha_of new-embed)"

before="$(cat "$sandbox/profile/sizes.json" "$sandbox/profile/model-digests.json")"
check "pin fails when the tree lists no such file" test "$("$script" pin 35b 2>/dev/null; echo $?)" = 1
check "pin fails for a size it does not know" test "$("$script" pin 9b 2>/dev/null; echo $?)" = 1
check "pin fails when the API has no answer" test "$(HF_ENDPOINT=https://hf.none "$script" pin 27b 2>/dev/null; echo $?)" = 1
check "pin refuses a revision that is not a commit sha" test "$("$script" pin 27b --revision main 2>/dev/null; echo $?)" = 1
check "a failed pin writes nothing" test "$(cat "$sandbox/profile/sizes.json" "$sandbox/profile/model-digests.json")" = "$before"
check "pin with no size is a usage error" test "$("$script" pin 2>/dev/null; echo $?)" = 2

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi

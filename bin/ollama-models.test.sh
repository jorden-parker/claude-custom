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

mkdir -p "$sandbox/stubbin"
cp -R "$repo/ollama" "$sandbox/ollama"
export OLLAMA_PROFILE_DIR="$sandbox/ollama"
export OLLAMA_REGISTRY="https://registry.test"
export PATH="$sandbox/stubbin:$PATH"

cat >"$sandbox/stubbin/ollama" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/ollama.log"
EOF
cat >"$sandbox/stubbin/curl" <<EOF
#!/bin/sh
case "\$*" in
  *api/tags*) cat "$sandbox/tags.json" ;;
  *registry.test/v2/library/qwen3/manifests/8b*) printf 'manifest-body' ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$sandbox/stubbin/ollama" "$sandbox/stubbin/curl"

pin_of() {
  jq -r --arg name "$1" '.[$name]' "$OLLAMA_PROFILE_DIR/model-digests.json"
}

cat >"$sandbox/tags.json" <<EOF
{"models": [
  {"name": "qwen3.8:27b-mlx", "digest": "$(pin_of qwen3.8:27b-mlx)"},
  {"name": "qwen3-embedding:0.6b", "digest": "0000"},
  {"name": "qwen3.8-27b-cc:latest", "digest": "1111"},
  {"name": "qwen3-4b-cc:latest", "digest": "2222"},
  {"name": "qwen3.8-9b-distill-cc:latest", "digest": "3333"},
  {"name": "hf.co/empero-ai/Qwen3.8-9B-Distill-GGUF:Q4_K_M", "digest": "4444"},
  {"name": "qwen3-vl:8b-instruct-q4_K_M", "digest": "5555"}
]}
EOF

listing="$("$script" list)"
check "list marks a base that matches its pin" grep -Eq '^pinned +qwen3.8:27b-mlx$' <<<"$listing"
check "list marks a base that misses its pin" grep -Eq '^mismatch +qwen3-embedding:0.6b$' <<<"$listing"
check "list marks a profile model" grep -Eq '^profile +qwen3.8-27b-cc:latest$' <<<"$listing"
check "list marks the retired side model as an orphan" grep -Eq '^orphan +qwen3-4b-cc:latest$' <<<"$listing"
check "list marks a -cc model no profile uses" grep -Eq '^orphan +qwen3.8-9b-distill-cc:latest$' <<<"$listing"
check "list marks a model from outside the Ollama library" grep -Eq '^third-party +hf.co/empero-ai/Qwen3.8-9B-Distill-GGUF:Q4_K_M$' <<<"$listing"
check "list marks other library models" grep -Eq '^other +qwen3-vl:8b-instruct-q4_K_M$' <<<"$listing"

"$script" prune </dev/null >"$sandbox/out" 2>&1
check "prune with no answer refuses" test "$?" = 1
check "prune without confirmation removes nothing" test ! -e "$sandbox/ollama.log"

printf 'n\n' | "$script" prune >"$sandbox/out" 2>&1
check "prune declined removes nothing" test ! -e "$sandbox/ollama.log"

"$script" prune --yes >"$sandbox/out" 2>&1
check "prune exits 0" test "$?" = 0
check "prune removes third-party and orphan models" test "$(cat "$sandbox/ollama.log")" = \
  "rm qwen3-4b-cc:latest qwen3.8-9b-distill-cc:latest hf.co/empero-ai/Qwen3.8-9B-Distill-GGUF:Q4_K_M"
rm -f "$sandbox/ollama.log"

printf 'y\n' | "$script" prune >"$sandbox/out" 2>&1
check "prune confirmed removes the same models" grep -q '^rm qwen3-4b-cc:latest qwen3.8-9b-distill-cc:latest ' "$sandbox/ollama.log"
check "prune lists what it will remove" grep -q 'hf.co/empero-ai/Qwen3.8-9B-Distill-GGUF:Q4_K_M' "$sandbox/out"
rm -f "$sandbox/ollama.log"

printf '{"models": [{"name": "qwen3-vl:8b-instruct-q4_K_M", "digest": "5555"}]}' >"$sandbox/tags.json"
"$script" prune --yes >/dev/null
check "prune with nothing to remove exits 0" test "$?" = 0
check "prune with nothing to remove runs no ollama rm" test ! -e "$sandbox/ollama.log"

"$script" pin qwen3:8b >/dev/null
check "pin records the registry manifest sha256" test "$(pin_of qwen3:8b)" = \
  "$(printf 'manifest-body' | shasum -a 256 | cut -c1-64)"
check "pin keeps the other pins" test "$(pin_of qwen3.8:27b-mlx)" = "$(jq -r '.["qwen3.8:27b-mlx"]' "$repo/ollama/model-digests.json")"
check "pin refuses a model outside the Ollama library" test "$("$script" pin hf.co/a/b:c 2>/dev/null; echo $?)" = 1
check "pin fails when the registry has no such tag" test "$("$script" pin qwen3:nope 2>/dev/null; echo $?)" = 1
check "a failed pin writes nothing" test "$(pin_of qwen3:nope)" = null
check "an unknown command is a usage error" test "$("$script" frobnicate 2>/dev/null; echo $?)" = 2

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi

#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/size-profile.sh"
. "$(dirname "${BASH_SOURCE[0]}")/weights-sha.sh"
user_presets_file="$session_config_dir/presets/models.ini"
embedding_file="$profile_dir/embedding.json"

server_url() {
  printf '%s\n' "${LLAMA_SERVER_URL:-http://127.0.0.1:11435}"
}

server_up() {
  [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$(server_url)/health" 2>/dev/null)" = 200 ]
}

server_build() {
  local build
  build="$(curl -sf -m 5 "$(server_url)/props" 2>/dev/null | jq -r '.build_info // empty' 2>/dev/null | sed -n 's/^b\([0-9][0-9]*\).*/\1/p')"
  if [ -z "$build" ]; then
    build="$("${LLAMA_SERVER_BIN:-llama-server}" --version 2>&1 | sed -n 's/.*(build \([0-9][0-9]*\).*/\1/p' | head -n 1)"
  fi
  [ -n "$build" ] && printf '%s\n' "$build"
}

model_entry() {
  curl -sf -m 5 "$(server_url)/models" 2>/dev/null |
    jq -ce --arg id "$1" 'first(.data[]? | select(.id == $id or ((.aliases // []) | index($id) != null)))' 2>/dev/null
}

model_listed() {
  model_entry "$1" >/dev/null
}

model_loaded() {
  [ "$(model_entry "$1" | jq -r '.status.value')" = loaded ]
}

model_resident_bytes() {
  model_loaded "$1" || return 1
  model_entry "$1" | jq -er '.meta.size // empty'
}

post_model_action() {
  curl -sf -m 30 -X POST "$(server_url)/models/$1" -H 'content-type: application/json' \
    -d "$(jq -cn --arg id "$2" '{model: $id}')" >/dev/null 2>&1
}

model_load() {
  local deadline
  model_loaded "$1" && return 0
  if ! post_model_action load "$1"; then
    echo "model-server: could not load $1" >&2
    return 1
  fi
  deadline=$((SECONDS + ${MODEL_LOAD_TIMEOUT:-600}))
  until model_loaded "$1"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "model-server: $1 did not load within ${MODEL_LOAD_TIMEOUT:-600}s" >&2
      return 1
    fi
    sleep "${MODEL_LOAD_POLL:-1}"
  done
}

model_unload() {
  model_loaded "$1" || return 0
  post_model_action unload "$1"
}

embedding_url() {
  printf '%s/v1/embeddings\n' "$(server_url)"
}

server_log_path() {
  printf '%s\n' "$session_config_dir/logs/llama-server.log"
}

ini_setting() {
  [ -r "$1" ] || return 1
  awk -v key="$2" '
    /^\[/ { in_star = ($0 == "[*]"); next }
    in_star {
      split($0, parts, "=")
      name = parts[1]; gsub(/[ \t]/, "", name)
      if (name == key) { value = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|[ \t]+$/, "", value); print value; found = 1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

server_setting() {
  ini_setting "$user_presets_file" "$1" || ini_setting "$profile_dir/server.ini" "$1"
}

plist_models_max() {
  [ -r "${LLAMA_SERVER_PLIST:-$HOME/Library/LaunchAgents/local.llama-server.plist}" ] || return 1
  sed -n 's:.*<string>\(.*\)</string>.*:\1:p' "${LLAMA_SERVER_PLIST:-$HOME/Library/LaunchAgents/local.llama-server.plist}" |
    awk 'previous == "--models-max" { print; found = 1; exit } { previous = $0 } END { exit found ? 0 : 1 }'
}

running_models_max() {
  curl -sf -m 5 "$(server_url)/props" 2>/dev/null | jq -er '.max_instances // empty' 2>/dev/null
}

models_max() {
  plist_models_max || running_models_max || echo 2
}

weights_dir() {
  printf '%s\n' "${CLAUDE_OLLAMA_WEIGHTS_DIR:-$session_config_dir/weights}"
}

size_gguf() {
  jq -er --arg size "$1" '.[$size].gguf // empty | "\(.repo) \(.revision) \(.file)"' "$profile_dir/sizes.json" 2>/dev/null
}

embedding_gguf() {
  jq -er '.gguf // empty | "\(.repo) \(.revision) \(.file)"' "$embedding_file" 2>/dev/null
}

weights_path() {
  local spec
  spec="$(size_gguf "$1")" || return 1
  printf '%s/%s\n' "$(weights_dir)" "${spec##* }"
}

gguf_pin() {
  jq -r --arg key "$1/$2" '.[$key] // empty' "$profile_dir/model-digests.json"
}

gguf_file_ok() {
  local repo revision file path pin
  read -r repo revision file <<<"$1"
  path="$(weights_dir)/$file"
  pin="$(gguf_pin "$repo" "$file")"
  [ -n "$pin" ] && [ -f "$path" ] && [ "$(file_sha256 "$path")" = "$pin" ]
}

weights_ok() {
  local spec
  spec="$(size_gguf "$1")" || return 1
  gguf_file_ok "$spec"
}

reject_weights() {
  echo "model-server: $1" >&2
  rm -f "$2"
  return 1
}

fetch_gguf() {
  local repo revision file dir pin part actual
  read -r repo revision file <<<"$1"
  gguf_file_ok "$1" && return 0
  pin="$(gguf_pin "$repo" "$file")"
  [ -n "$pin" ] || { echo "model-server: $repo/$file has no pin in ollama/model-digests.json; refusing to download" >&2; return 1; }
  dir="$(weights_dir)"
  mkdir -p "$dir"
  part="$dir/$file.part"
  echo "model-server: downloading $repo/$file (pinned $revision)" >&2
  if ! curl -fL --retry 3 -C - -o "$part" "${HF_ENDPOINT:-https://huggingface.co}/$repo/resolve/$revision/$file"; then
    echo "model-server: the download of $file stopped; run the same command again to resume it" >&2
    return 1
  fi
  actual="$(shasum -a 256 "$part" | cut -d' ' -f1)"
  [ "$actual" = "$pin" ] || reject_weights "$file has sha256 $actual, but ollama/model-digests.json pins $pin; not keeping it" "$part" || return 1
  mv "$part" "$dir/$file"
  remember_sha256 "$dir/$file" "$(file_stamp "$dir/$file")" "$actual" 2>/dev/null || true
  "$repo_dir/bin/gguf-inspect" "$dir/$file" >&2 || reject_weights "$file failed inspection; not keeping it" "$dir/$file"
}

fetch_weights() {
  local spec
  spec="$(size_gguf "$1")" || { echo "model-server: size $1 has no pinned gguf in sizes.json" >&2; return 1; }
  fetch_gguf "$spec"
}

fetch_embedding_weights() {
  local spec
  spec="$(embedding_gguf)" || { echo "model-server: ollama/embedding.json has no pinned gguf" >&2; return 1; }
  fetch_gguf "$spec"
}

#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
script="$repo/bin/model-cleanup"
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

present() { [ -e "$1" ]; }
absent() { [ ! -e "$1" ]; }
contains() { grep -qF -- "$2" <<<"$1"; }
lacks() { ! grep -qE -- "$2" <<<"$1"; }
removed_models() { cat "$sandbox/ollama.log" 2>/dev/null; }

export HOME="$sandbox/home"
export OLLAMA_PROFILE_DIR="$sandbox/ollama"
export OLLAMA_HOST="http://ollama.test"
export BENCH_MODELS="$sandbox/bench-models"
export HF_HOME="$sandbox/huggingface"
export LLAMA_CACHE="$sandbox/llama-cache"
export TORCH_HOME="$sandbox/torch"
export MODEL_CLEANUP_MIN_KB=0
unset XDG_CACHE_HOME
export PATH="$sandbox/stubbin:$PATH"

mkdir -p "$sandbox/stubbin" "$OLLAMA_PROFILE_DIR"
cp "$repo"/ollama/settings.*.json "$repo/ollama/sizes.json" "$repo/ollama/model-digests.json" "$OLLAMA_PROFILE_DIR/"

cat >"$sandbox/stubbin/ollama" <<EOF
#!/bin/sh
[ "\$1" = rm ] || exit 1
shift
printf '%s\n' "\$@" >> "$sandbox/ollama.log"
EOF
cat >"$sandbox/stubbin/curl" <<EOF
#!/bin/sh
case "\$*" in
  *ollama.test/api/tags*) [ -f "$sandbox/tags.json" ] && cat "$sandbox/tags.json" || exit 7 ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$sandbox/stubbin/ollama" "$sandbox/stubbin/curl"

cat >"$sandbox/tags.json" <<EOF
{"models": [
  {"name": "qwen3.8:27b-mlx", "digest": "$(jq -r '.["qwen3.8:27b-mlx"]' "$OLLAMA_PROFILE_DIR/model-digests.json")", "size": 17000000000},
  {"name": "qwen3.8-27b-cc:latest", "digest": "1111", "size": 17000000000},
  {"name": "qwen3.6:35b-mlx", "digest": "2222", "size": 22000000000},
  {"name": "qwen3.6-35b-cc:latest", "digest": "3333", "size": 22000000000},
  {"name": "qwen3-4b-cc:latest", "digest": "4444", "size": 2500000000},
  {"name": "hf.co/someone/Thing-GGUF:Q4_K_M", "digest": "5555", "size": 5000000000},
  {"name": "llama3.2:3b", "digest": "6666", "size": 2000000000}
]}
EOF

seed() {
  rm -rf "$OLLAMA_PROFILE_DIR/weights" "$BENCH_MODELS" "$HF_HOME" "$LLAMA_CACHE" "$TORCH_HOME" "$HOME" "$sandbox/ollama.log"
  mkdir -p "$OLLAMA_PROFILE_DIR/weights" "$HOME/.claude-ollama/weights" "$HOME/.ollama/models/blobs" \
    "$BENCH_MODELS/qwen-mlx" "$HF_HOME/hub" "$LLAMA_CACHE" "$TORCH_HOME/hub" "$HOME/.cache/whisper" \
    "$HOME/.lmstudio/models/pub/repo" "$HOME/Downloads" "$HOME/Library/Application Support/Jan" \
    "$HOME/Library/Caches" "$HOME/project/node_modules/pkg"
  printf 'half' >"$OLLAMA_PROFILE_DIR/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
  printf 'left' >"$OLLAMA_PROFILE_DIR/weights/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
  printf 'old' >"$HOME/.claude-ollama/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf"
  printf 'blob' >"$HOME/.ollama/models/blobs/sha256-1.gguf"
  printf 'mlx' >"$BENCH_MODELS/qwen-mlx/model.safetensors"
  printf 'hub' >"$HF_HOME/hub/model"
  printf 'cached' >"$LLAMA_CACHE/model.gguf"
  printf 'torch' >"$TORCH_HOME/hub/model.pt"
  printf 'whisper' >"$HOME/.cache/whisper/base.pt"
  printf 'lm' >"$HOME/.lmstudio/models/pub/repo/a.gguf"
  printf 'lm' >"$HOME/.lmstudio/models/pub/repo/b.safetensors"
  printf 'loose' >"$HOME/Downloads/loose.gguf"
  printf 'notes' >"$HOME/Downloads/notes.txt"
  printf 'jan' >"$HOME/Library/Application Support/Jan/m.gguf"
  printf 'cache' >"$HOME/Library/Caches/other.gguf"
  printf 'dep' >"$HOME/project/node_modules/pkg/model.onnx"
  mkdir -p "$HOME/Downloads/proj"
  printf 'keep' >"$HOME/Downloads/proj/keep.txt"
  printf 'trap' >"$HOME/Downloads/proj"$'\n'"x.gguf"
}

seed
dry_output="$("$script" --dry-run 2>&1)"
dry_status=$?
check "dry run exits 0" test "$dry_status" -eq 0
check "dry run names the partial download in the repo" contains "$dry_output" "Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
check "dry run names a GGUF left after its import" contains "$dry_output" "weights/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
check "dry run names the llama.cpp-era weights folder" contains "$dry_output" "$HOME/.claude-ollama/weights"
check "dry run names the Ollama model no profile uses" contains "$dry_output" "qwen3-4b-cc:latest"
check "dry run names a third-party Ollama model" contains "$dry_output" "hf.co/someone/Thing-GGUF:Q4_K_M"
check "dry run names another Ollama model" contains "$dry_output" "llama3.2:3b"
check "dry run shows an Ollama model's size" contains "$dry_output" "4.7 GiB"
check "dry run never offers a profile model" lacks "$dry_output" "qwen3.8-27b-cc"
check "dry run never offers a pinned base" lacks "$dry_output" "qwen3.8:27b-mlx"
check "dry run never offers the Ollama store itself" lacks "$dry_output" "sha256-1"
check "dry run names the bench-off folder" contains "$dry_output" "$BENCH_MODELS"
check "dry run names the Hugging Face cache" contains "$dry_output" "$HF_HOME"
check "dry run names the llama.cpp cache" contains "$dry_output" "$LLAMA_CACHE"
check "dry run names the PyTorch cache" contains "$dry_output" "$TORCH_HOME"
check "dry run names the Whisper cache" contains "$dry_output" "$HOME/.cache/whisper"
check "dry run lists the Whisper folder, not its files" lacks "$dry_output" "base.pt"
check "dry run finds a store outside the project" contains "$dry_output" "$HOME/.lmstudio/models/pub/repo/a.gguf"
check "dry run finds a loose model file" contains "$dry_output" "$HOME/Downloads/loose.gguf"
check "dry run finds a model in Application Support" contains "$dry_output" "Application Support/Jan/m.gguf"
check "dry run skips files that are not models" lacks "$dry_output" "notes.txt"
check "dry run skips the rest of Library" lacks "$dry_output" "Caches/other.gguf"
check "dry run skips node_modules" lacks "$dry_output" "model.onnx"
check "dry run reports a name with a newline instead of offering it" contains "$dry_output" "skipped a name with a newline or tab"
check "dry run never offers the folder such a name points into" lacks "$dry_output" "^ +$HOME/Downloads/proj$"
check "dry run sums what it found" contains "$dry_output" "would free up to"
check "dry run removes no file" present "$OLLAMA_PROFILE_DIR/weights/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
check "dry run removes no Ollama model" test -z "$(removed_models)"

seed
yes_output="$("$script" --yes 2>&1)"
yes_status=$?
check "--yes exits 0" test "$yes_status" -eq 0
check "--yes removes the partial download" absent "$OLLAMA_PROFILE_DIR/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
check "--yes removes the leftover GGUF" absent "$OLLAMA_PROFILE_DIR/weights/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
check "--yes keeps the repo's weights folder" present "$OLLAMA_PROFILE_DIR/weights"
check "--yes removes the llama.cpp-era weights" absent "$HOME/.claude-ollama/weights"
check "--yes removes the Ollama model no profile uses" grep -qx 'qwen3-4b-cc:latest' "$sandbox/ollama.log"
check "--yes keeps a third-party Ollama model, which always asks" lacks "$(removed_models)" "hf.co"
check "--yes keeps another Ollama model, which always asks" lacks "$(removed_models)" "llama3.2"
check "--yes keeps the profile models" lacks "$(removed_models)" "qwen3.8|qwen3.6"
check "--yes keeps the Ollama store" present "$HOME/.ollama/models/blobs/sha256-1.gguf"
check "--yes removes the bench-off folder" absent "$BENCH_MODELS"
check "--yes removes the Hugging Face cache" absent "$HF_HOME"
check "--yes removes the llama.cpp cache" absent "$LLAMA_CACHE"
check "--yes removes the PyTorch cache" absent "$TORCH_HOME"
check "--yes removes the Whisper cache" absent "$HOME/.cache/whisper"
check "--yes keeps model files it found, which always ask" present "$HOME/.lmstudio/models/pub/repo/a.gguf"
check "--yes keeps a loose model file" present "$HOME/Downloads/loose.gguf"
check "--yes says what it kept" contains "$yes_output" "kept: run without --yes"
check "--yes reports what it freed" contains "$yes_output" "freed"

seed
"$script" --yes --drop 35b >/dev/null 2>&1
check "--drop 35b removes its model" grep -qx 'qwen3.6-35b-cc:latest' "$sandbox/ollama.log"
check "--drop 35b removes its base" grep -qx 'qwen3.6:35b-mlx' "$sandbox/ollama.log"
check "--drop 35b keeps the 27b" lacks "$(removed_models)" "qwen3.8"

drop_output="$("$script" --drop 99b 2>&1)"
drop_status=$?
check "--drop of an unknown size exits 2" test "$drop_status" -eq 2
check "--drop of an unknown size names it" contains "$drop_output" "99b"

seed
mv "$sandbox/tags.json" "$sandbox/tags.json.off"
down_output="$("$script" --yes 2>&1)"
down_status=$?
mv "$sandbox/tags.json.off" "$sandbox/tags.json"
check "a silent Ollama does not stop the cleanup" test "$down_status" -eq 0
check "a silent Ollama is reported" contains "$down_output" "Ollama is not answering"
check "a silent Ollama still lets the caches go" absent "$HF_HOME"

rm -rf "$HOME" "$OLLAMA_PROFILE_DIR/weights" "$BENCH_MODELS" "$HF_HOME" "$LLAMA_CACHE" "$TORCH_HOME"
mv "$sandbox/tags.json" "$sandbox/tags.json.full"
printf '{"models": []}' >"$sandbox/tags.json"
clean_output="$("$script" --yes 2>&1)"
mv "$sandbox/tags.json.full" "$sandbox/tags.json"
check "a clean machine has nothing to clean" contains "$clean_output" "nothing to clean"

seed
printf 'y\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\ny\nn\n' | "$script" >/dev/null 2>&1
check "answering yes removes the first group" absent "$OLLAMA_PROFILE_DIR/weights/Qwen3.8-27B-UD-Q4_K_XL.gguf.part"
check "answering no keeps the llama.cpp-era weights" present "$HOME/.claude-ollama/weights"
check "answering no removes no Ollama model" test -z "$(removed_models)"
check "answering no keeps the bench-off folder" present "$BENCH_MODELS/qwen-mlx"
check "answering no keeps a found store" present "$HOME/.lmstudio/models/pub/repo/a.gguf"
check "answering yes removes that folder's model files" absent "$HOME/Downloads/loose.gguf"
check "removing a folder's model files keeps its other files" present "$HOME/Downloads/notes.txt"
check "a name with a newline never removes the folder it names" present "$HOME/Downloads/proj/keep.txt"
check "answering no keeps the last folder" present "$HOME/Library/Application Support/Jan/m.gguf"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi

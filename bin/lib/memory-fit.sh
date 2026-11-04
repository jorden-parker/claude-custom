#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/size-profile.sh"
lease_bin="${CLAUDE_OLLAMA_LEASE_BIN:-$repo_dir/bin/ollama-lease}"
bytes_per_gib=1073741824
fit_json=""
fit_margin=""

lease_on() {
  [ "${CLAUDE_OLLAMA_LEASE:-}" != 0 ]
}

fit_on() {
  [ "${CLAUDE_OLLAMA_FIT:-}" != 0 ]
}

run_fit() {
  "$lease_bin" fit --model "${model:?}" --num-ctx "$1"
}

gib() {
  awk -v bytes="$1" -v unit="$bytes_per_gib" 'BEGIN { printf "%.1f GiB", bytes / unit }'
}

read_fit() {
  fit_json="$1"
  fit_margin="$(jq -r .margin_bytes <<< "$1")"
}

fit_summary() {
  local model_bytes kv_bytes total_bytes free_bytes
  IFS=$'\t' read -r model_bytes kv_bytes total_bytes free_bytes < <(
    jq -r '[.model_bytes, .kv_bytes, .total_bytes, .free_bytes] | @tsv' <<< "$fit_json")
  echo "model $(gib "$model_bytes") + kv $(gib "$kv_bytes") = $(gib "$total_bytes") of $(gib "$free_bytes") free"
}

fit_fits() {
  [ "$(jq -r .fits <<< "$1")" = true ]
}

fit_shortfall() {
  gib "${fit_margin#-}"
}

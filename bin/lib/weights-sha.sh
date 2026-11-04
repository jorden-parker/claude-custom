#!/bin/bash
weights_sha_cache() {
  printf '%s\n' "${CLAUDE_OLLAMA_SHA_CACHE:-$HOME/.claude-ollama/cache/weights-sha256.tsv}"
}

file_stamp() {
  stat -f '%z %m' "$1" 2>/dev/null || stat -c '%s %Y' "$1"
}

cached_sha256() {
  local cache
  cache="$(weights_sha_cache)"
  [ -f "$cache" ] || return 1
  awk -F '\t' -v path="$1" -v stamp="$2" '$1 == path && $2 == stamp { print $3; found = 1 } END { exit found ? 0 : 1 }' "$cache"
}

remember_sha256() {
  local cache kept
  cache="$(weights_sha_cache)"
  mkdir -p "$(dirname "$cache")"
  kept="$([ -f "$cache" ] && awk -F '\t' -v path="$1" '$1 != path' "$cache" || true)"
  { [ -z "$kept" ] || printf '%s\n' "$kept"; printf '%s\t%s\t%s\n' "$1" "$2" "$3"; } > "$cache.tmp"
  mv "$cache.tmp" "$cache"
}

file_sha256() {
  local stamp sha
  stamp="$(file_stamp "$1")"
  if sha="$(cached_sha256 "$1" "$stamp")"; then
    printf '%s\n' "$sha"
    return 0
  fi
  sha="$(shasum -a 256 "$1" | cut -c1-64)"
  [ "${#sha}" -eq 64 ] || return 1
  remember_sha256 "$1" "$stamp" "$sha" 2>/dev/null || true
  printf '%s\n' "$sha"
}

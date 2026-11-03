#!/bin/bash
node_choice=""
node_spec_source=""

nvm_dir() {
  printf '%s' "${NVM_DIR:-$HOME/.nvm}"
}

nvmrc_file() {
  local folder
  folder="$(pwd -P)"
  while :; do
    if [ -f "$folder/.nvmrc" ]; then
      printf '%s' "$folder/.nvmrc"
      return 0
    fi
    [ "$folder" != / ] || return 1
    folder="$(dirname "$folder")"
  done
}

first_word_of() {
  tr -d '\r' < "$1" | awk 'NF { print $1; exit }'
}

node_spec_source_file() {
  local rc
  if rc="$(nvmrc_file)"; then
    printf '%s' "$rc"
  elif [ -f "$(nvm_dir)/alias/default" ]; then
    printf 'default'
  else
    return 1
  fi
}

nvm_version_spec() {
  if [ "$node_spec_source" = default ]; then
    first_word_of "$(nvm_dir)/alias/default"
  else
    first_word_of "$node_spec_source"
  fi
}

follow_nvm_alias() {
  local spec="$1" hops=0
  while [ -f "$(nvm_dir)/alias/$spec" ] && [ "$hops" -lt 5 ]; do
    spec="$(first_word_of "$(nvm_dir)/alias/$spec")"
    hops=$((hops + 1))
  done
  printf '%s' "$spec"
}

installed_nvm_version() {
  local spec="$1" prefix folder version
  case "$spec" in
    node | stable | 'lts/*' | '') prefix= ;;
    *) prefix="v${spec#v}" ;;
  esac
  for folder in "$(nvm_dir)/versions/node"/v*; do
    version="${folder##*/}"
    case "$version" in
      "$prefix" | "$prefix".*) echo "$version" ;;
      v*) [ -n "$prefix" ] || echo "$version" ;;
    esac
  done | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -n 1
}

node_spec_label() {
  if [ "$node_spec_source" = default ]; then
    printf 'nvm default'
  else
    printf 'nvm %s from %s' "$1" "$node_spec_source"
  fi
}

use_nvm_node() {
  local spec version node_bin
  node_spec_source=
  [ -d "$(nvm_dir)/versions/node" ] || return 0
  node_spec_source="$(node_spec_source_file)" || return 0
  spec="$(nvm_version_spec)"
  version="$(installed_nvm_version "$(follow_nvm_alias "$spec")")"
  node_bin="$(nvm_dir)/versions/node/$version/bin"
  if [ -z "$version" ] || [ ! -x "$node_bin/node" ]; then
    echo "claude-ollama: node: nvm has no node $spec installed (from $node_spec_source); using $(command -v node || echo none)" >&2
    return 0
  fi
  export PATH="$node_bin:$PATH"
  node_choice="$node_bin/node ($(node_spec_label "$spec"))"
  echo "claude-ollama: node: $node_choice" >&2
}

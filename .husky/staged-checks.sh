#!/usr/bin/env bash
# managed by git-precommit-setup
set -eu

MAX_BYTES=1048576
status=0

staged_files() {
  git diff --cached --name-only --diff-filter=AM -z
}

check_conflict_markers() {
  staged_files | while IFS= read -r -d '' file; do
    if git show ":$file" | grep -Iq '^\(<<<<<<< \|=======$\|>>>>>>> \)'; then
      echo "conflict markers: $file"
      exit 1
    fi
  done
}

check_large_files() {
  staged_files | while IFS= read -r -d '' file; do
    size=$(git cat-file -s ":$file")
    if [ "$size" -gt "$MAX_BYTES" ]; then
      echo "large file ($size bytes, limit $MAX_BYTES): $file"
      exit 1
    fi
  done
}

check_secrets() {
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks protect --staged --redact --no-banner
    return
  fi
  staged_files | while IFS= read -r -d '' file; do
    if git show ":$file" | grep -IEq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|xox[baprs]-[0-9A-Za-z-]{10,}|sk-[A-Za-z0-9]{20,}'; then
      echo "possible secret: $file"
      exit 1
    fi
  done
}

check_conflict_markers || status=1
check_large_files || status=1
check_secrets || status=1
exit $status

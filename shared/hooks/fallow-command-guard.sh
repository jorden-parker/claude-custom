#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/fallow-lib.sh"
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
SESSION="$(jq -r '.session_id // "nosession"' <<<"$INPUT")"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT")"
[ -z "$CMD" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

has_json_format() {
  local prev=""
  for w in "$@"; do
    case "$w" in
      --format=json|--output=json|-f=json) return 0 ;;
      json) case "$prev" in --format|--output|-f) return 0 ;; esac ;;
    esac
    prev="$w"
  done
  return 1
}

fix_is_applied_without_preview() {
  local yes=0 dry=0 w
  for w in "$@"; do
    [ "$w" = "--yes" ] && yes=1
    [ "$w" = "--dry-run" ] && dry=1
  done
  [ "$yes" -eq 1 ] && [ "$dry" -eq 0 ] && [ ! -f "$(fallow_marker_dir)/$SESSION" ]
}

check_fallow_segment() {
  local sub="" w
  for w in "$@"; do
    case "$w" in
      --help|-h|--version|-V) return 0 ;;
      -*) ;;
      *) [ -z "$sub" ] && sub="$w" ;;
    esac
  done
  case "$sub" in
    explain|init|agent|hooks|help|watch|viz|migrate|audit-cache|baselines|recommend) return 0 ;;
  esac
  if [ "$sub" = "fix" ] && fix_is_applied_without_preview "$@"; then
    deny "Preview before applying: run 'fallow fix --dry-run --format json' in this session, review the preview, then run 'fallow fix --yes --format json'."
  fi
  has_json_format "$@" || deny "Always pass --format json when running Fallow as an agent. Rerun as: fallow ${sub:-<command>} ... --format json"
}

gate_git_write() {
  local root report
  root="$(fallow_project_root "${CWD:-$PWD}")" || return 0
  cd "$root" || return 0
  report="$(fallow_audit_report)"
  if [ $? -eq 1 ]; then
    deny "Blocked: fallow audit reports a fail verdict for this changeset. Fix the findings (or remove dead code) and try again.
$report"
  fi
}

check_npx_segment() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      fallow) shift; check_fallow_segment "$@"; return ;;
      *) return ;;
    esac
  done
}

check_git_segment() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      commit|push) gate_git_write; return ;;
      -c|-C|--git-dir|--work-tree|--namespace|--config-env) shift; [ "$#" -gt 0 ] && shift ;;
      -*) shift ;;
      *) return ;;
    esac
  done
}

check_segment() {
  case "$1" in
    fallow|*/fallow) shift; check_fallow_segment "$@" ;;
    npx) shift; check_npx_segment "$@" ;;
    git) shift; check_git_segment "$@" ;;
  esac
}

while IFS= read -r segment; do
  read -ra words <<<"$segment"
  [ "${#words[@]}" -gt 0 ] || continue
  check_segment "${words[@]}"
done < <(printf '%s\n' "$CMD" | tr ';|&()' '\n')
exit 0

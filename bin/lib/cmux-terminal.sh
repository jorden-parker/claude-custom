#!/bin/bash
in_cmux_terminal() {
  case "${CMUX_SOCKET_PATH:-}" in
    /*) [ -S "$CMUX_SOCKET_PATH" ] && command -v cmux >/dev/null ;;
    *) return 1 ;;
  esac
}

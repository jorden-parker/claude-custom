#!/bin/sh
unalias claude 2>/dev/null
claude() { env CLAUDE_CUSTOM_HOME="$CLAUDE_CUSTOM_HOME" "$CLAUDE_CUSTOM_HOME/personal/launch" "$@"; }

#!/bin/sh
unalias claude 2>/dev/null
claude() { env CLAUDE_CUSTOM_HOME="$CLAUDE_CUSTOM_HOME" claude --settings "$("$CLAUDE_CUSTOM_HOME/personal/settings-path")" "$@"; }

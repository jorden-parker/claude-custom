unalias claude 2>/dev/null
claude() { command \claude --settings "$CLAUDE_CUSTOM_HOME/personal/settings.tokens.json" "$@"; }

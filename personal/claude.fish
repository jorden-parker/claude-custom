function claude --wraps claude --description 'claude with the personal token overlay layered on user settings'
    command claude --settings $CLAUDE_CUSTOM_HOME/personal/settings.tokens.json $argv
end

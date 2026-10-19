function claude --wraps claude --description 'claude with the personal token overlay layered on user settings'
    env CLAUDE_CUSTOM_HOME=$CLAUDE_CUSTOM_HOME claude --settings ($CLAUDE_CUSTOM_HOME/personal/settings-path) $argv
end

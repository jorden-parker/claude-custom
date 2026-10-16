function claude --wraps claude --description 'claude with the personal token overlay layered on user settings'
    command claude --settings ~/src/.claude-custom/personal/settings.tokens.json $argv
end

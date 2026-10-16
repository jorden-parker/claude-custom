# Claude Code token overlays

Additive overlays. Nothing here replaces a base file; each layer is merged by
Claude Code or applied per launch.

## Layer order (later wins for scalars; arrays concatenate; `env` merges per key)

1. `~/.claude/settings.json` (user) + `personal/settings.tokens.json` merged in
2. `<repo>/.claude/settings.json` (project, untouched)
3. `<repo>/.claude/settings.local.json` (local) ← `project/settings.local.json`
4. `--settings ollama/settings.<size>.json` (CLI flag layer, work harness only)
5. Managed policy (untouched, always wins)

## Personal install

```sh
mkdir -p ~/.claude/hooks
ln -s ~/src/.claude-custom/shared/hooks/bash-output-guard.py ~/.claude/hooks/bash-output-guard.py
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak ~/src/.claude-custom/personal/settings.tokens.json > ~/.claude/settings.json
echo '@~/src/.claude-custom/personal/CLAUDE.tokens.md' >> ~/.claude/CLAUDE.md
```

`jq *` replaces arrays instead of concatenating them. Your current base has no
`permissions` or `hooks`, so this is safe today; if that changes, merge those
arrays by hand.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: restore `settings.json.bak`, delete the `@` line, remove the symlink.

## Work harness (Ollama)

```sh
ln -s ~/src/.claude-custom/bin/claude-ollama ~/.local/bin/claude-ollama
ollama pull qwen3.8:27b-mlx && ollama create qwen3.8-27b-cc -f ollama/Modelfile.27b
ollama pull qwen3.8:9b-mlx  && ollama create qwen3.8-9b-cc  -f ollama/Modelfile.9b
claude-ollama 27b    # or: claude-ollama 9b
```

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

## Hook test

`shared/hooks/bash-output-guard.test.sh`

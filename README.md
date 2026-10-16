# Claude Code token overlays

Additive overlays. Nothing here replaces a base file; each layer is merged by
Claude Code or applied per launch.

## Layer order (higher number wins for scalars; lists such as `permissions.*` and `hooks.*` concatenate; `env` merges per key)

1. `~/.claude/settings.json` (user, never edited by this repo)
2. `<repo>/.claude/settings.json` (project, untouched)
3. `<repo>/.claude/settings.local.json` (local) ← `project/settings.local.json`
4. `--settings` (CLI layer, one file only): `personal/settings.tokens.json` via
   the fish `claude` function, or `ollama/settings.<size>.json` via
   `claude-ollama`
5. Managed policy (untouched, always wins)

`--settings` is a single slot. Passing it twice keeps only the last file, so
`claude --settings other.json` drops the personal overlay for that session.

## Personal install

```sh
mkdir -p ~/.claude/hooks ~/.config/fish/functions
ln -s ~/src/.claude-custom/shared/hooks/bash-output-guard.py ~/.claude/hooks/bash-output-guard.py
ln -s ~/src/.claude-custom/personal/claude.fish ~/.config/fish/functions/claude.fish
echo '@~/src/.claude-custom/personal/CLAUDE.tokens.md' >> ~/.claude/CLAUDE.md
```

`~/.claude/settings.json` is left as is. The overlay loads on top of it on every
`claude` launch from fish. It only adds keys the user file doesn't set. Lists
and hooks concatenate, and `env` merges per key. Launches outside fish (IDE
extensions, the desktop app, scripts calling `claude` directly) don't get the
overlay. Run `command claude` to skip it.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: remove the two symlinks and delete the `@` line.

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

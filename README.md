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
~/src/.claude-custom/bin/claude-custom install
```

This wires every shell it finds: zsh (`~/.zshrc`), bash (`~/.bashrc`,
`~/.bash_profile`), ksh (`~/.kshrc`) and fish
(`~/.config/fish/conf.d/claude-custom.fish`). Rc edits sit between
`# >>> claude-custom >>>` markers and put `~/.local/bin` on PATH. It also links
`claude-ollama`, `claude-custom` and the Bash output hook, adds the `@` import
to `~/.claude/CLAUDE.md`, and rebuilds the Ollama models whose base model is
pulled. Re-running it is safe. `~/.claude/settings.json` is left as is: the
overlay loads on top of it via `--settings` on every interactive `claude`
launch. Scripts, IDE extensions, the desktop app and `claude-ollama` don't get
it. Run `command claude` to skip it once.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: `claude-custom uninstall`.

## Work harness (Ollama)

```sh
ollama pull qwen3.8:27b-mlx
ollama pull qwen3.8:9b-mlx
claude-custom install
claude-ollama 27b
```

`claude-custom install` creates the `-cc` models from `ollama/Modelfile.<size>`
once the base models are pulled. Use `claude-ollama 9b` for the small model.

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

## Hook test

`shared/hooks/bash-output-guard.test.sh`

## Another machine / updating

Clone anywhere and install once:

```sh
git clone <remote> ~/src/.claude-custom
~/src/.claude-custom/bin/claude-custom install
```

After that, `claude-custom update` pulls (fast-forward only) and re-runs
install. Most changes are live after a plain `git pull`, because every link and
rc block points into the repo. `update` also picks up new links and rebuilds
changed Ollama models.

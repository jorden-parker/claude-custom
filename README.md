# Claude Code token overlays

![verify](https://github.com/jorden-parker/claude-custom/actions/workflows/verify.yml/badge.svg)

Additive overlays: settings, hooks and prompts for Claude Code, plus a launcher
that runs it against local Ollama models. Nothing here replaces a base file;
each layer is merged by Claude Code or applied per launch.

## Install

```sh
git clone <remote> ~/src/.claude-custom
~/src/.claude-custom/bin/claude-custom install
```

`install` wires the `claude` shell function into zsh, bash, ksh and fish, and
links `claude-ollama`, `claude-tools` and `claude-custom` into `~/.local/bin`.
Revert with `claude-custom uninstall`. Prerequisites and what else install
changes are in [install](docs/install.md).

## Use

- `claude`: the personal overlay (hooks, token discipline).
- `claude-ollama [27b|35b]`: Claude Code on a local model.
- `claude-tools`: edit which built-in tools Claude Code loads.
- `make test`: every test suite, the one CI runs. The Stop hook runs only the
  tests for the files the agent edited.

## Read more

- [How settings layer](docs/layers.md)
- [Install details and updating](docs/install.md)
- [Enforced preferences, hooks and tests](docs/hooks.md)
- [Work harness (Ollama)](docs/ollama.md)
- [Tools TUI](docs/tools-tui.md)
- [Prompt-cache probe](docs/cache-probe.md)
- [Semantic code search](docs/code-search.md)

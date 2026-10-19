# model-picker

A terminal menu for choosing which Ollama profile `claude-ollama` launches.
Built with [Bubble Tea](https://charm.land/libs/), Bubbles and Lip Gloss.

## Run

```sh
claude-custom ollama          # opens the picker, then launches the chosen size
claude-ollama 28b             # unknown size: opens the picker too
go run . ../ollama            # the picker on its own; prints the chosen size
```

`claude-ollama` rebuilds the binary on each launch (instant when nothing
changed). Keys: `↑/k`, `↓/j`, `enter` to launch or set up, `esc`/`q`/`ctrl+c` to
cancel.

## Profiles

The list comes from the profile directory. Each `settings.<size>.json` that has
a matching `Modelfile.<size>` becomes one entry. It shows the size, the `model`
from the settings file, and the `FROM` line of the Modelfile. A settings file
with no `model` is an error, and a settings file with no Modelfile is skipped.

When `side.Modelfile` exists, the last row is "Set up side model". Enter on it
runs `ollama pull <FROM>` and `ollama create <name> -f side.Modelfile`, where
the name is the `ANTHROPIC_DEFAULT_HAIKU_MODEL` all settings files share. The
output goes to stderr, and the menu stays open with a ready or failed status.

The last row is always "Set up embedding model". Enter on it runs `ollama pull`
for the model `semantic_search` uses: `CODE_SEARCH_MODEL` when set, otherwise
`qwen3-embedding:0.6b`. It needs no config file. Output and status work the same
as the side model row.

The menu renders on stderr in the alternate screen, so a setup run's output
doesn't leave a second copy of the menu behind. Only the chosen size goes to
stdout. Exit codes: 0 when a size is chosen, 1 when the menu is cancelled, 2 for
usage errors or when no profiles are configured.

## Test

```sh
go test ./...
```

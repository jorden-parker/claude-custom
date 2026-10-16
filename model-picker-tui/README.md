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
changed). Keys: `↑/k`, `↓/j`, `enter` to launch, `esc`/`q`/`ctrl+c` to cancel.

## Profiles

The list comes from the profile directory. Each `settings.<size>.json` that has
a matching `Modelfile.<size>` becomes one entry. It shows the size, the `model`
from the settings file, and the `FROM` line of the Modelfile. A settings file
with no `model` is an error, and a settings file with no Modelfile is skipped.

The menu renders on stderr. Only the chosen size goes to stdout. Exit codes: 0
when a size is chosen, 1 when the menu is cancelled, 2 for usage errors or when
no profiles are configured.

## Test

```sh
go test ./...
```

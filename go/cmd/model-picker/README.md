# model-picker

A terminal menu for choosing which Ollama profile `claude-ollama` launches.
Built with [Bubble Tea](https://charm.land/libs/), Bubbles and Lip Gloss.

## Run

```sh
claude-custom ollama          # opens the picker, then launches the chosen size
claude-ollama 28b             # unknown size: opens the picker too
cd go && go run ./cmd/model-picker ../ollama  # the picker on its own; prints the chosen size
```

`claude-custom install` builds the binary, and `claude-ollama` rebuilds it on
launch only when a Go source file is newer than the binary. Keys: `↑/k`, `↓/j`,
`enter` to launch or set up, `esc`/`q`/`ctrl+c` to cancel.

## Profiles

The list comes from the profile directory. Each `settings.<size>.json` whose
size is a top-level key of `sizes.json` becomes one entry. It shows the size,
the `model` from the settings file, and that size's `base` from `sizes.json`. A
settings file with no `model` is an error, a size missing from `sizes.json` is
skipped, and a malformed `sizes.json` is an error.

The last row is always "Set up embedding model". Enter on it runs
`claude-ollama prepare-embedding`, which fetches the model `semantic_search`
uses: `CODE_SEARCH_MODEL` when set, otherwise `qwen3-embedding:0.6b`. The output
goes to stderr, and the menu stays open with a ready or failed status.

The menu renders on stderr in the alternate screen, so a setup run's output
doesn't leave a second copy of the menu behind. Only the chosen size goes to
stdout. Exit codes: 0 when a size is chosen, 1 when the menu is cancelled, 2 for
usage errors or when no profiles are configured.

## Test

```sh
cd go && go test ./...
```

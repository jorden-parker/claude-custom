# Plan: Ollama prompt-cache probe

Status: planned, not implemented.

## Goal

Find out how much prefill the local models actually skip thanks to Ollama's
prompt (KV) cache, so tuning choices rest on numbers instead of guesses.

Why now: Ollama issue
[#17829](https://github.com/ollama/ollama/issues/17829) reports prefix reuse
failing on `qwen3.8:27b-mlx`, and
[#18267](https://github.com/ollama/ollama/issues/18267) says the MLX runner
snapshots the cache every 8192 tokens. Either could mean most prefill time is
spent re-reading the same prompt.

## Deliverable

`bin/ollama-cache-probe [27b|35b|MODEL] [--prefix-tokens N]`: a Python 3
stdlib script (no pip installs) that sends a fixed set of requests to
`localhost:11434` and prints one table row per scenario.

- Sizes resolve to the `-cc` model through `ollama/settings.<size>.json`, the
  same way `bin/claude-ollama` does. Any other argument is used as a model name.
- `--prefix-tokens` sets the shared prefix length (default 20000, roughly a real
  Claude Code system prompt plus a few file reads).
- `--base-url` overrides the server address for tests.

## Measurement

Each request goes to `/api/chat` with `stream: false` and a fixed `num_ctx`.
From each response, read:

- `prompt_eval_count`: tokens actually evaluated
- `prompt_eval_duration`: prefill time
- total prompt tokens, from the first cold run of the same prompt

Hit rate = `1 - prompt_eval_count / total prompt tokens`.

First step during implementation: check whether this Ollama version reports
only uncached tokens in `prompt_eval_count`. If it reports the full count, fall
back to prefill time per token compared with the cold run.

## Scenarios

| #   | Scenario      | Requests                                                     | Expected if caching works                    |
| --- | ------------- | ------------------------------------------------------------ | -------------------------------------------- |
| 1   | Cold          | `P + q1` after unloading the model (`keep_alive: 0`)         | Full prefill                                 |
| 2   | Same prefix   | `P + q2`                                                     | Only `q2` evaluated                          |
| 3   | Growing chat  | `P + q1 + a1 + q2`, like a Claude Code turn                  | Only `a1 + q2` evaluated                     |
| 4   | Early edit    | `P` with one token changed near the start                    | Full prefill                                 |
| 5   | Late edit     | `P` changed at about 16k tokens                              | Re-prefill from the last 8192-token snapshot |
| 6   | Eviction      | short unrelated prompt `X`, then `P + q2`                    | With one slot: full prefill of `P`           |
| 7   | Side model    | request to a small model (e.g. `qwen3.5:4b`), then `P + q2`  | Only `q2` evaluated, if models keep caches   |

`P` is built from fixed text (repo files concatenated deterministically) so runs
compare across days. Scenario 7 is skipped when the small model is not pulled.

## Output

A plain table on stdout: scenario, prompt tokens, evaluated tokens, hit %,
prefill seconds. Add `--json` for machine-readable output. The script prints the
server settings it can see (`ollama ps`, model, `num_ctx`) above the table, and
reminds the user that `OLLAMA_NUM_PARALLEL` needs a server restart to compare 1
against 2.

## Tests (written first)

`bin/ollama-cache-probe.test.sh`, added to `.claude/verify`:

- A stub server (Python `http.server`, started by the test) returns canned
  `/api/chat` responses with set `prompt_eval_count` values.
- Expect correct hit-rate maths, a skipped row for a missing side model, size
  resolution from a temporary `ollama/` directory, and a clear error when the
  server is unreachable.
- No test touches a real Ollama server.

## Follow-up decisions this unlocks

- Scenario 6 shows eviction → try `OLLAMA_NUM_PARALLEL=2`, or drop `Agent` from
  `--tools`.
- Scenario 7 shows a separate cache → delegate side work to a small model.
- Scenarios 2–3 show no reuse → report upstream with the table, and consider the
  non-MLX GGUF build of the model.

## Out of scope

Changing any settings, Modelfiles or server env. The probe only measures.

## Open questions

- Does Ollama's Anthropic-compatible `/v1/messages` endpoint (what Claude Code
  uses) cache the same way as `/api/chat`? A later version could replay one
  captured Claude Code request through it.

# Prompt-cache probe

`bin/ollama-cache-probe` measures how much prefill llama-server skips through
its prompt cache. It sends six fixed scenarios (cold, growing chat, same prefix,
late and early edits, eviction) to `/v1/messages` and prints one row each. It
changes no settings.

```sh
bin/ollama-cache-probe                       # the 27b's preset, qwen3.8-27b-cc
bin/ollama-cache-probe qwen3.6-35b-cc --prefix-tokens 8000 --json
bin/ollama-cache-probe --replay ~/.claude-ollama/proxy/record
```

The first argument is a llama-server preset id. `--base-url` picks the server
(default `$LLAMA_SERVER_URL`, else `http://127.0.0.1:11435`). The header names
the server, the model, the loaded model's `n_ctx` and the presets loaded before
the run.

Hit % comes from the uncached token count (`input_tokens`). If the server
reports full counts instead, the probe warns and scores by prefill time per
token against the cold step. The late edit sits at 80% of the prefix, about 16k
tokens at the default 20000.

While it runs, it prints each step on stderr
(`[n/6] <scenario>: <what it is doing>`) and how long it took; the cold step
unloads and reloads the model, so it is the slowest. If the model is already
loaded, it notes that requests queue behind any other session using it. After
the table it prints one plain verdict line each for the cache, growing chat and
eviction. A cache that isn't reused points at the preset's `cache-reuse` and
`ctx-checkpoints` in `~/.claude-ollama/presets/models.ini`
(`ollama-agent -set ctx-checkpoints=256`); a failed eviction suggests more
prompt cache (`ollama-agent -set cache-ram=16384`).

`--replay DIR` sends the bodies the messages proxy recorded
(`CLAUDE_OLLAMA_PROXY_RECORD=1`) in the order they were written, after a reload,
and prints the hit % per request (from `cache_read_input_tokens`) and how many
consecutive requests reused the cache.

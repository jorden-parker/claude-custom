# Prompt-cache probe

`bin/ollama-cache-probe` measures how much prefill the local Ollama server skips
through its prompt cache. It sends seven fixed scenarios (cold, same prefix,
growing chat, early and late edits, eviction, side model) and prints one row
each. It changes no settings.

```sh
bin/ollama-cache-probe 27b                   # or 35b, or any model name
bin/ollama-cache-probe 27b --prefix-tokens 8000 --json
```

Hit % comes from uncached token counts. If the server reports full counts
instead, the probe warns and scores by prefill time per token. The late edit
sits at 80% of the prefix, about 16k tokens at the default 20000.

While it runs, it prints each step on stderr
(`[n/7] <scenario>: <what it is doing>`) and how long it took; the cold step
unloads and reloads the model, so it is the slowest. If the model is already
loaded, it notes that requests queue behind any other session using it. After
the table it prints one plain verdict line each for the cache, growing chat,
eviction and side model. A failed eviction suggests `OLLAMA_NUM_PARALLEL=2`; a
cache that isn't reused suggests a GGUF build.

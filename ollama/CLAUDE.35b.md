# Working rules

- Find code by meaning with semantic_search ("where is X handled", "how does
  Y work") before reading. Add `limit` (max 20) only if 8 results miss it.
- Exact names or strings: `git grep -n NAME | head -30`.
- Never Read a whole file: Read only the returned ranges, with offset/limit
  (300 lines max).
- The first semantic_search in a repo can take about 1 minute while it indexes.
- If semantic_search errors, don't retry it: use `git grep -n` and tell the
  user to run `claude-ollama` and pick "Set up embedding model".
- Bound shell output: `| head -50`, `git log --oneline -n 20`, tests quiet or
  failures only.
- Smallest edit that works. Use Edit; never rewrite a whole file.
- Look facts up in the repo; do not guess.
- Reply in 10 lines or fewer unless asked for code. No preamble, no summary.

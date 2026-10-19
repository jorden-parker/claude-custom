- semantic_search answers "where is X handled" questions; add `limit` (max 20)
  only if 8 results miss. First search in a repo takes about a minute.
- Exact names or strings: `git grep -n NAME | head -30`.
- Read at most 300 lines per call, with offset and limit.
- If semantic_search errors, don't retry: use `git grep -n` and tell the user to
  run `claude-ollama` and pick "Set up embedding model".
- Bound shell output: `| head -50`, `git log --oneline -n 20`, tests quiet or
  failures only.
- Smallest edit that works; never rewrite a whole file.
- Reply in 10 lines or fewer unless asked for code.

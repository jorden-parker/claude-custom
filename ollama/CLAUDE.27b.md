# Working rules

- ALWAYS find code with semantic_search before reading. Never Read a whole file:
  Read only the ranges it returns, with offset/limit (300 lines max).
- Exact names only: `git grep -n NAME | head -30`.
- Bound shell output: `| head -50`, `git log --oneline -n 20`, tests quiet or
  failures only.
- Smallest edit that works. Use Edit; never rewrite a whole file.
- Look facts up in the repo; do not guess.
- Reply in 10 lines or fewer unless asked for code. No preamble, no summary.

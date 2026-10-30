- mcp__code-search__semantic_search answers "where is X handled" questions with
  the code's own words; add `limit` (max 20) only if 8 results miss. A reply
  ending in "words only" means synonyms won't match: rephrase with identifiers.
- Exact names or strings, after that first search:
  `git grep -n NAME | head -30`.
- Read at most 300 lines per call, with offset and limit.
- Read git history and GitHub PRs, issues and CI through the mcp__repo__ tools
  (no permission prompt), not Bash `git log`/`git diff`.
- Write a PR description with /pr-draft and a PR review with /pr-review-draft;
  the user edits and posts the draft in the console.
- If semantic_search errors, don't retry: use `git grep -n`. If the launch said
  the embedding pull failed, tell the user to pick "Set up embedding model" in
  `claude-ollama`.
- Bound shell output: `| head -50`, tests quiet or failures only.
- Smallest edit that works; never rewrite a whole file.
- Reply in 10 lines or fewer unless asked for code.
- Dev servers: mcp__dev__dev_status first and use the URL it returns; never
  guess a port. Start one with mcp__dev__dev_start, not Bash `pnpm dev`.
- Test UI changes in the browser: mcp__dev__page_check opens the page (pass url
  for a full local URL such as https://127.0.0.1:4000/; never Bash open),
  mcp__dev__page_snapshot lists elements with refs, mcp__dev__page_act
  clicks/fills/presses by ref. Fix every error and warning they return.
- Bash runs in a sandbox without prompts: it writes this project, a temp dir and
  ~/.cache/claude-sandbox (where Go, npm, pnpm, pip and uv keep their caches),
  and reaches localhost, github.com and the npm, Go and PyPI registries; other
  hosts prompt. `gh`, `cmux`, `short`, `git push` and `git commit` each ask
  first.

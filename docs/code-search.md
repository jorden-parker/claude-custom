# Semantic code search

`claude-ollama` starts `shared/mcp/code-search.py`, a stdlib-only MCP server
with one tool, `semantic_search`. It embeds the repo with `qwen3-embedding:0.6b`
(pulled on launch if missing) and returns `file:start-end` ranges with a score
and a one-line preview, so the model reads only those lines. `claude-ollama`
drops Grep and Glob (`--tools Bash,Read,Edit,Write,Agent,WebFetch`, plus bare
deny rules), and `tool-nudge.py` refuses the first two Bash text searches of a
turn until the tool has been called; exact names go through `git grep -n` after
that.

- Files: `git ls-files` plus untracked, non-ignored files. Lockfiles, minified
  files, images, binaries and files over 200 KB are skipped.
- Chunks: 40-line windows every 30 lines, vectors cut to 256 dimensions.
- Index: `.git/code-search/index.json`. Each search re-embeds only files whose
  content changed, so the first search in a repo is slow (about a minute for
  this one) and later ones take well under a second. `claude-ollama` starts
  `code-search.py --index` in the background on launch (set
  `CLAUDE_OLLAMA_NO_INDEX=1` to skip), so the first search is usually fast.
- `CODE_SEARCH_OLLAMA_URL` and `CODE_SEARCH_MODEL` override the server and
  model. `claude-ollama` and the model picker follow `CODE_SEARCH_MODEL` too.
- If the pull on launch fails, run `claude-ollama` and pick "Set up embedding
  model" in the menu.
- `ollama/CLAUDE.local.md` tells the model when to search (questions about what
  code does), when to use `git grep -n` (exact names), and to fall back to
  `git grep` and point you at that menu row when the search errors.

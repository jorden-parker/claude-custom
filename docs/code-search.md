# Semantic code search

`claude-ollama` starts `shared/mcp/code-search.py`, a stdlib-only MCP server
with one tool, `semantic_search`. It embeds the repo with `qwen3-embedding:0.6b`
(pulled on launch if missing) and returns `file:start-end` ranges with a score
and a one-line preview, so the model reads only those lines. `claude-ollama`
drops Grep and Glob (`--tools Bash,Read,Edit,Write,Agent`, plus bare deny
rules), and `tool-nudge.py` refuses the first two Bash text searches of a turn
until the tool has been called; exact names go through `git grep -n` after that.

- Files: `git ls-files` plus untracked, non-ignored files. Lockfiles, minified
  files, images, binaries and files over 200 KB are skipped.
- Chunks: 40-line windows every 30 lines. Each chunk stores its words
  (identifiers split on case and underscores, lowercased) and, once
  `--index` has run with the embedding model loaded, a vector cut to 256
  dimensions.
- Ranking: BM25 over the words, always, with no model call. When
  `GET /api/ps` shows the embedding model loaded, the query is embedded too
  and the two rankings are merged by reciprocal rank fusion; otherwise the
  reply ends with a "words only" line. The server never loads the model, so
  a search can never evict the main or side model.
- Index: `.git/code-search/index.json`, written only by
  `code-search.py --index`, which `claude-ollama` runs in the background on
  launch (set `CLAUDE_OLLAMA_NO_INDEX=1` to skip). The server keeps the index
  in memory, re-tokenizes changed files on each search (milliseconds) and
  reloads the file when a later `--index` run wrote a newer one. Vectors are
  added only by `--index`, only while the model is loaded; a file changed
  during a session is searched by words until the next launch.
- `CODE_SEARCH_OLLAMA_URL` and `CODE_SEARCH_MODEL` override the server and
  model. `claude-ollama` and the model picker follow `CODE_SEARCH_MODEL` too.
- If the pull on launch fails, run `claude-ollama` and pick "Set up embedding
  model" in the menu.
- `ollama/CLAUDE.local.md` tells the model when to search (questions about what
  code does), when to use `git grep -n` (exact names), and to fall back to
  `git grep` and point you at that menu row when the search errors.

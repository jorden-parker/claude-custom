# Semantic code search

`claude-ollama` starts `shared/mcp/code-search.py`, a stdlib-only MCP server
with one tool, `semantic_search`. It embeds the repo through llama-server's
`/v1/embeddings` with the preset aliased `qwen3-embedding:0.6b` (section
`[qwen3-embedding-0.6b]`; its GGUF, pinned in `ollama/embedding.json`, is
downloaded on launch if missing) and returns `file:start-end` ranges with a
score and a one-line preview, so the model reads only those lines.
`claude-ollama` drops Grep and Glob
(`--tools Bash,Read,Edit,Write,Skill,TaskStop`, plus bare deny rules); exact
names go through `git grep -n`.

- Files: `git ls-files` plus untracked, non-ignored files. Lockfiles, minified
  files, images, binaries and files over 200 KB are skipped.
- Chunks: 40-line windows every 30 lines. Each chunk stores its words
  (identifiers split on case and underscores, lowercased) and, once `--index`
  has run with the embedding model loaded, a vector cut to 256 dimensions.
- Ranking: BM25 over the words, always, with no model call. When the router's
  `GET /models` shows the embedding preset `loaded`, the query is embedded too
  and the two rankings are merged by reciprocal rank fusion; otherwise the reply
  ends with a "words only" line. The server never loads the model, so a search
  can never evict the main model.
- When llama-server's `models-max` (`[router]` in `ollama/server.ini`;
  default 2) is 2 or more, `claude-ollama` exports `CODE_SEARCH_EMBED=1` to the
  search server and the indexer and loads the embedding preset beside the
  session's. With that variable set the server embeds whether or not `/models`
  shows the preset loaded, and an embedding failure degrades to a "words only"
  reply that names the error instead of a tool error. See
  [docs/ollama.md](ollama.md) for the memory trade-off.
- Index: `.git/code-search/index.json`, written only by
  `code-search.py --index`, which `claude-ollama` runs in the background on
  launch (set `CLAUDE_OLLAMA_NO_INDEX=1` to skip). It runs with
  `--watch-pid <launcher>` and stops embedding when that session ends; one
  indexer runs per repo (`.git/code-search/index.lock`; a second exits with
  `index already running`), and vectors made before a stop, a kill or a server
  error are saved, so the next launch only embeds what is left. The server keeps
  the index in memory, re-tokenizes changed files on each search (milliseconds)
  and reloads the file when a later `--index` run wrote a newer one. Vectors are
  added only by `--index`, only while the model is loaded; a file changed during
  a session is searched by words until the next launch.
- `LLAMA_SERVER_URL` (default `http://127.0.0.1:11435`) picks the server and
  `CODE_SEARCH_MODEL` the preset. `claude-ollama` and the model picker follow
  `CODE_SEARCH_MODEL` too.
- If the download on launch fails, run `claude-ollama prepare-embedding`, or run
  `claude-ollama` and pick "Set up embedding model" in the menu, which runs the
  same command.
- `ollama/CLAUDE.local.md` tells the model when to search (questions about what
  code does), when to use `git grep -n` (exact names), and to fall back to
  `git grep` and point you at that menu row when the search errors.

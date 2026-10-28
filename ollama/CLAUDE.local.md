- mcp__code-search__semantic_search answers "where is X handled" questions with
  the code's own words; add `limit` (max 20) only if 8 results miss. A reply
  ending in "words only" means synonyms won't match: rephrase with identifiers.
- Exact names or strings, after that first search:
  `git grep -n NAME | head -30`.
- Read at most 300 lines per call, with offset and limit.
- Read git history and GitHub PRs, issues and CI through the mcp__repo__ tools
  (no permission prompt), not Bash `git log`/`git diff`.
- `gh` in Bash is read-only. It goes through a broker; the session has no GitHub
  login. Use it when a skill or the user asks for `gh` output, or to shape JSON
  with `--jq`. Only these forms work:
  - `gh pr list [--state open|closed|merged|all] [--author A] [--search Q] [--limit N]`
  - `gh pr view N [--comments] [--json f1,f2] [--jq EXPR]`
  - `gh pr diff N|BRANCH [--name-only]`
  - `gh pr checks N [--json f1,f2] [--jq EXPR]`
  - `gh issue list [--state S] [--search Q] [--limit N]`, `gh issue view N`
  - `gh run list [--branch B] [--limit N]`, `gh run view ID [--log-failed]`
  - `gh api repos/{owner}/{repo}/pulls/N/comments` (inline review comments)
  - Another repo: add `-R owner/name`, or pass a PR or issue URL. Only this repo
    and the user's listed repos work.
- `gh` refuses everything else: merge, comment, review, create, checkout, auth,
  other `api` paths.
- Shortcut: `short` in Bash runs the user's Shortcut CLI through a broker; the
  session has no token. Only these forms work:
  - Find: `short search WORDS` (`short find` is the same), e.g.
    `short search owner:me state:"In Progress"`; filters
    `-o OWNER -s STATE -l LABEL -t TEXT -e N -y TYPE`, output `-f FORMAT`, `-q`
  - Read: `short story ID`, `short epics`, `short epic view ID`,
    `short epic stories ID`, `short iterations [-C]`, `short iteration view ID`,
    `short iteration stories ID`, `short labels`, `short label stories ID`,
    `short label epics ID`, `short teams`, `short team view ID`,
    `short team stories ID`, `short members [-s NAME]`, `short workflows`,
    `short docs`, `short doc view ID`
  - Change, only when the user asked (it writes to Shortcut):
    `short story ID -c "comment" -s STATE -e N -o OWNER -l LABEL`,
    `short story ID --task "text"`, `short story ID --task-complete "text"`,
    `short create -t TITLE [-d TEXT] [-s STATE] [-o OWNER] [-l LABEL]`
- `short` refuses install, api, workspace, deletes, `--open`, `--git-branch`,
  `--from-git`, `--download` and `search --save`.
- A refusal that lists what is allowed (fields, qualifiers, flags, commands):
  retry once with an allowed form that does the same job. If none does, or the
  error says "read-only", "not on this machine's gh-repos list" or "broker is
  not running", stop and tell the user. Never work around it with curl, git
  remotes or tokens.
- If semantic_search errors, don't retry: use `git grep -n`. If the launch said
  the embedding pull failed, tell the user to pick "Set up embedding model" in
  `claude-ollama`.
- Bound shell output: `| head -50`, tests quiet or failures only.
- Smallest edit that works; never rewrite a whole file.
- Reply in 10 lines or fewer unless asked for code.
- Dev servers: mcp__dev__dev_status first and use the URL it returns; never
  guess a port. Start one with mcp__dev__dev_start, not Bash `pnpm dev`.
- Test UI changes in the browser: mcp__dev__page_check opens the page,
  mcp__dev__page_snapshot lists elements with refs, mcp__dev__page_act
  clicks/fills/presses by ref. Fix every error and warning they return.

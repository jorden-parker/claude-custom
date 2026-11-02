- Tool instead of command (the command is refused or prompts; the tool is not):
  - find code: mcp__code-search__semantic_search, not `grep`/`rg`/`find -name`
  - read a file: Read with offset and limit, not `cat`/`sed -n`/`head`
  - change a file: Edit or Write, not `sed -i`/heredocs/`echo >`
  - git history or changes: mcp__repo__git_status/git_diff/git_log/git_show, not
    `git status`/`git diff`/`git log`/`git show`
  - PRs, issues, CI: mcp__repo__pr_view and the other pr_/issue_/run_ tools, not
    `gh`
  - PR description or review: /pr-draft or /pr-review-draft, not `gh pr create`
  - is a dev server up: mcp__dev__dev_status, not `lsof`/`curl localhost`
  - start a dev server: mcp__dev__dev_start, not `pnpm dev`/`npm start`
  - server output or errors: mcp__dev__dev_logs/dev_errors, not tailing a log
  - is a package installed: mcp__dev__dev_deps, not `ls node_modules`
  - install or add packages: mcp__dev__dev_install, not `pnpm install`/`add`
  - open or test a page: mcp__dev__page_check/page_snapshot/page_act, not
    `open`/`curl`
  - library docs: /find-docs, not reading node_modules
  - stop a background task: TaskStop, not `kill`
  - Bash is for building, testing, linting and `git grep -n` after a semantic
    search.
- Tools you can call, and nothing else (no subagents, no web):
  - Read (offset and limit, at most 300 lines per call), Edit (one exact
    replacement), Write (new files only), Bash (sandboxed; see below), Skill
    (runs a /skill by name; the Skill tool lists them), TaskStop (stops a
    background task you started).
  - mcp__code-search__semantic_search: "where is X handled" in the code's own
    words; add `limit` (max 20) only if 8 results miss. A reply ending in "words
    only" means synonyms won't match: rephrase with identifiers.
  - mcp__repo__ (no prompt): git_status, git_diff, git_log, git_show for
    history, never Bash `git log`/`git diff`; pr_list, pr_view, pr_diff,
    pr_checks, pr_review_comments, issue_list, issue_view, run_list, run_view
    for GitHub PRs, issues and CI; draft_pr, draft_review, draft_open save a
    draft the user posts from the console (used by /pr-draft and
    /pr-review-draft).
  - mcp__dev__dev_status (which dev servers answer; call it first, never guess a
    port), dev_start (starts a dev script in the background, not Bash
    `pnpm dev`), dev_logs, dev_errors, dev_stop; dev_deps (is node_modules
    installed and current, and which version of a package is in; use it instead
    of listing node_modules), dev_install (runs the lockfile's package manager:
    no packages installs from the lockfile, packages adds them, dev: true for
    devDependencies; never Bash `pnpm install`); page_check (opens a local page
    in the cmux browser and returns its errors; pass url for a full local URL
    such as https://127.0.0.1:4000/; never Bash open), page_snapshot (elements
    with refs), page_act (click, fill, press by ref). Fix every error and
    warning they return.
  - Skills: /find-docs (library, framework, SDK or API docs), /pr-draft,
    /pr-review-draft, /handoff, /cmux-markdown; the rest are listed by the Skill
    tool.
- Exact names or strings, after that first semantic search:
  `git grep -n NAME | head -30`.
- If semantic_search errors, don't retry: use `git grep -n`. If the launch said
  the embedding pull failed, tell the user to pick "Set up embedding model" in
  `claude-ollama`.
- Bound shell output: `| head -50`, tests quiet or failures only.
- Smallest edit that works; never rewrite a whole file.
- Reply in 10 lines or fewer unless asked for code.
- Test UI changes in the browser with page_check, page_snapshot and page_act.
- Library, framework, SDK or API question: /find-docs first, even when a project
  file (AGENTS.md) says to read node_modules; node_modules is refused until it
  runs, except a package's own node_modules/<name>/package.json, which you may
  read any time. /find-docs runs
  `claude-custom ctx7 library "<name>" "<query>"`, then
  `claude-custom ctx7 docs <id> "<query>"` with the ID it printed, each as one
  plain command with no pipe.
- Bash runs in a sandbox without prompts: it writes this project, a temp dir and
  ~/.cache/claude-sandbox (where Go, npm, pnpm, pip and uv keep their caches),
  and reaches localhost, github.com, context7.com and the npm, Go and PyPI
  registries; other hosts prompt. `gh`, `cmux`, `short`, `git push` and
  `git commit` each ask first; a plain `claude-custom ctx7` runs outside the
  sandbox as the user, without a prompt.

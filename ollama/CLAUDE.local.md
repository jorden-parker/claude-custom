- Tool instead of command (the command is refused or prompts; the tool is not):
  - read a file: Read with offset and limit, not `cat`/`sed -n`/`head`
  - change a file: Edit or Write, not `sed -i`/heredocs/`echo >`
  - library docs: /find-docs, not reading node_modules
  - stop a background task: TaskStop, not `kill`
  - Bash is for building, testing, linting, searching and git.
- Tools you can call, and nothing else (no subagents, no web):
  - Read (offset and limit, at most 300 lines per call), Edit (one exact
    replacement), Write (new files only), Bash (sandboxed; see below), Skill
    (runs a /skill by name from the skills list in the system reminder),
    TaskStop (stops a background task you started).
  - Skills: /find-docs (library, framework, SDK or API docs), /handoff,
    /cmux-markdown; when a task matches a listed skill's description, call Skill
    with its name before anything else.
- Find code: `git grep -n NAME | head -30` for exact names, `git grep -n -i`
  with a few likely words for "where is X handled".
- Git: `git status --short`, `git diff --stat` then one file's diff,
  `git log -n 20 --oneline`, `git show --stat REV`. GitHub: `gh` (it asks
  first).
- Dev servers: start one with Bash `pnpm -C DIR dev` and
  `run_in_background: true`, read the URL from its output, never guess a port.
- Is a package installed: Read `node_modules/<name>/package.json`, not
  `ls node_modules`. Install or test: one plain `pnpm -C DIR install|add|test`.
- Bound shell output: `| head -50`, tests quiet or failures only.
- Reply in 10 lines or fewer unless asked for code.
- When a "Context budget" note arrives, finish the edit, call Skill handoff with
  `save`, then stop and say a relaunch is coming.
- Library, framework, SDK or API question: /find-docs first, even when a project
  file (AGENTS.md) says to read node_modules; Read inside node_modules is
  refused until it runs, except a package's own
  node_modules/<name>/package.json, which you may read any time. /find-docs runs
  `claude-custom ctx7 library "<name>" "<query>"`, then
  `claude-custom ctx7 docs <id> "<query>"` with the ID it printed, each as one
  plain command with no pipe.
- Rule cards: a hook adds a short card the first time a session touches a file
  type, folder, command or tool it covers. Follow the card from then on.

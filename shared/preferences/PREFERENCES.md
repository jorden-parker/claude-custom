# Coding preferences

Hooks check these after every edit and before you finish. A failed check blocks
you until it is fixed.

## Code style

These rules apply to every project and every language, with no exceptions.

- Self-describing code: a name says what it holds or does, so the structure
  explains itself. Not `tmp`, `data2`, `obj`, `handleStuff`, `utils.ts`:
  `parsedConfig`, `retryCount`, `closeIdleSockets`, `profile-rules.ts`. (nudged
  by name-nudge hook)
- Keep designs simple: SOLID, KISS, YAGNI. Add only what the task needs.
- No comments, including lint suppressions. Rewrite unclear code instead.
  (enforced by edit-check hook)
- Small functions that do one thing.
- Formatting and lint rules come from the project's own configs. (enforced by
  gofmt, go vet, prettier, eslint, ruff, shellcheck)

## Workflow

- New git worktree: before any other work, symlink `node_modules` and other
  untracked files it needs (`.env*`, local config, build caches) from the main
  checkout into it.
- Library, framework, SDK or API question: `/find-docs` (Context7) before
  answering from memory.
- TDD: write a failing test, make it pass with the smallest change, refactor.
  (enforced by tdd-guard hook: a code file can be edited only after a test in
  its package was edited and a test command ran)
- Tests must pass before you finish. (enforced at Stop by `.claude/verify`, or
  the repo's make/go/pnpm test command)
- UI changes: after tests pass, check the page in a real browser with
  `/cmux-browser` and read the console for errors.

## Token discipline

- Grep/Glob before Read. Read only the line range you need.
- Bound shell output: `| head -50`, `-n 20`, `--oneline`, `-q`.
- One targeted search beats several broad ones.
- Wide searches go to a subagent; keep only its conclusion.
- Lead with the result. No preamble, no recap.

# Coding preferences

Hooks check these after every edit and before you finish. A failed check blocks
you until it is fixed.

## Code style

These rules apply to every project and every language, with no exceptions.

- Write clean, tidy, self-describing code. Clear names and structure explain it;
  nothing else should have to.
- Keep designs simple: SOLID, KISS, YAGNI. Add only what the task needs.
- Use clear, specific names for variables, functions and files.
- No comments, including lint suppressions. Rewrite unclear code instead.
  (enforced by edit-check hook)
- Small functions that do one thing.
- Formatting and lint rules come from the project's own configs. (enforced by
  gofmt, go vet, prettier, eslint, ruff, shellcheck)

## Workflow

- TDD: write a failing test, make it pass with the smallest change, refactor.
- Tests must pass before you finish. (enforced by `.claude/verify` at Stop)
- TS/JS: Fallow runs before you finish. Fix its findings; use
  `npx fallow explain <issue-type>` when unclear; remove dead code, never
  suppress it. (enforced by stop-verify hook)
- UI changes: after tests pass, check the page in a real browser with
  `/cmux-browser` and read the console for errors.

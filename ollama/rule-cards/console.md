---
triggers:
  - path: web/console/
---

web/console (Next.js; AI Elements vendored in `src/components`): no raw colour
in a TS file, palettes live in `src/app/globals.css`. Tests are vitest, run as
`pnpm -C web/console test`. Routes read only `CLAUDE_CONSOLE_STATE_DIR`, and
every POST checks its `Origin`. Check a changed page with the /cmux-browser
skill (`cmux browser open URL`) and read its console errors.

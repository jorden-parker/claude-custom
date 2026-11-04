---
triggers:
  - command: pnpm
---

pnpm: run it as one plain command, `pnpm -C DIR install|add|test` (no `cd &&`,
no pipe, no `;`). `pnpm exec`, `dlx`, `x` and `create` are refused. Start a dev
server as Bash `pnpm -C DIR dev` with `run_in_background: true`, never in the
foreground; its output gives the URL and the errors.

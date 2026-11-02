---
triggers:
  - command: pnpm
---

pnpm: run it as one plain command, `pnpm -C DIR install|add|test` (no `cd &&`,
no pipe, no `;`), or call mcp__dev__dev_install. `pnpm exec`, `dlx`, `x` and
`create` are refused. Start a dev server with mcp__dev__dev_start, never
`pnpm dev`.

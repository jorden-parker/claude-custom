---
triggers:
  - suffix: .ts,.tsx
---

TS/JS: Fallow runs before you finish. Fix its findings; use
`npx fallow explain <issue-type>` when unclear; remove dead code, never suppress
it. Tests are vitest (`X.test.ts` beside `X.ts`). Test UI changes in the browser
with page_check, page_snapshot and page_act.

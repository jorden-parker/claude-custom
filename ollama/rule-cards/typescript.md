---
triggers:
  - suffix: .ts,.tsx
---

TS/JS: Fallow audits every edited file at Stop; fix each finding (ask
`npx fallow explain <issue-type>` when one is unclear) and delete dead code
rather than suppressing it. Tests are vitest (`X.test.ts` beside `X.ts`). Test
UI changes in the browser with page_check, page_snapshot and page_act.

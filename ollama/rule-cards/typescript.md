---
triggers:
  - suffix: .ts,.tsx
---

TS/JS: Fallow audits every edited file at Stop; fix each finding (ask
`npx fallow explain <issue-type>` when one is unclear) and delete dead code
rather than suppressing it. Tests are vitest (`X.test.ts` beside `X.ts`). Test
UI changes in the cmux browser through the /cmux-browser skill: open the page,
snapshot it, click through the change and fix every console error.

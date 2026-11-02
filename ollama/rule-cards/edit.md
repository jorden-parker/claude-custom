---
triggers:
  - tool: Edit,MultiEdit
---

TDD, enforced: before editing a code file, edit its test (X.test.sh, X_test.go,
X.test.ts) and run it; the edit is refused until both happened. Smallest edit
that works; never rewrite a whole file. Match the file's naming and idiom; add
no comments.

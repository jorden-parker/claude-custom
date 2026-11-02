---
triggers:
  - suffix: .sh
---

Shell: stay bash 3.2 compatible (macOS `/bin/bash`): no `declare -A`,
`${var,,}`, `mapfile` or `read -N`. `shellcheck` and `bash -n` must pass. A
script `X` has its test in `X.test.sh` beside it, which prints `all passed`, or
`FAIL:` lines and exits 1.

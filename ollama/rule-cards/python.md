---
triggers:
  - suffix: .py
---

Python: stdlib only, no third-party imports; `ruff` must pass. Run a script that
reads untrusted files with `python3 -I`, so nothing beside them is imported. A
script `X.py` has its test in `X.test.sh` beside it, which prints `all passed`.

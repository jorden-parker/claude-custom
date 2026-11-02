---
triggers:
  - tool: Bash
---

Bash runs in a sandbox without prompts: it writes this project, a temp dir and
~/.cache/claude-sandbox (where Go, npm, pnpm, pip and uv keep their caches), and
reaches localhost, github.com, context7.com and the npm, Go and PyPI registries;
other hosts prompt. `gh`, `cmux`, `short`, `git push` and `git commit` each ask
first; a plain `claude-custom ctx7` runs outside the sandbox as the user,
without a prompt.

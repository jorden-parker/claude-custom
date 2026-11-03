---
name: find-docs
description:
  Current docs, API references and code examples for any library, framework,
  SDK, CLI or cloud service through Context7. Use on /find-docs and before
  answering any question that names a library, even a well-known one, since
  training data lags API changes.
---

# Find docs

Context7 serves current, version-specific docs through the `ctx7` CLI, run
through `claude-custom ctx7`, which prints at most 80 lines. Two steps, always
in this order, each as one plain command (no pipe, no `cd`, no variable):

```
claude-custom ctx7 library "<name>" "<query>"
claude-custom ctx7 docs <id> "<query>" [--language L]
```

## 1. Resolve the library

Use the official name with its punctuation ("Next.js", "Three.js"). The query is
required and ranks the results. Pick the best ID by name match, snippet count,
source reputation and benchmark score. IDs start with `/` (`/vercel/next.js`).
When the user names a version, use the version ID the output lists
(`/vercel/next.js/v16.2.9`). Skip this step only when the user gives an ID.

## 2. Query the docs

One concept per `docs` call: split "routing and auth and caching" into one call
each. Describe what to look up, not the task: "React useEffect cleanup with
async operations", never "hooks". Add `--language` when the user's language is
known. Read only the snippets that answer; the output holds titled code snippets
and prose info snippets.

Never put secrets, credentials or proprietary code in a query. At most 3
commands per question: after that, answer from the best result you have.

## Auth and errors

Lookups work anonymously. `CONTEXT7_API_KEY` in the environment or a
`ctx7 login` raises the quota. On a quota error ("Monthly quota reached", "quota
exceeded") tell the user, suggest a key from https://context7.com/dashboard,
then answer from memory flagged as possibly outdated. Never fall back silently.
A plain `claude-custom ctx7 ...` command runs outside Claude Code's sandbox
(`excludedCommands` in both overlays), as the user, with their own network,
proxy and certificates; a pipe or any other command beside it sends the whole
line back into the sandbox. If it reports `fetch failed`, tell the user rather
than retrying. If it prints
`the Context7 CLI is not installed; run: claude-custom install`, tell the user
to run that command in their own terminal and answer from memory flagged as
possibly outdated; the session cannot install it. The CLI version is pinned as
`ctx7_version` in `bin/claude-custom`.

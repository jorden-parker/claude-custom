---
name: find-docs
description:
  Current docs, API references and code examples for any library, framework,
  SDK, CLI or cloud service through Context7. Use on /find-docs and before
  answering any question that names a library, even a well-known one, since
  training data lags API changes.
---

# Find docs

Context7 serves current, version-specific docs through the `ctx7` CLI. Two
steps, always in this order, each piped through `| head -80`:

```
npx ctx7@latest library "<name>" "<query>" | head -80
npx ctx7@latest docs <id> "<query>" [--language L] | head -80
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

Lookups work anonymously. `CONTEXT7_API_KEY` in the environment raises the
quota; the sandbox cannot run `ctx7 login`. On a quota error ("Monthly quota
reached", "quota exceeded") tell the user, suggest a key from
https://context7.com/dashboard, then answer from memory flagged as possibly
outdated. Never fall back silently. Needs Node 22.13 or newer.

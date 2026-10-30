---
name: pr-draft
description:
  Draft a pull request for the current branch from the project's pull request
  template, saved for the user to edit and post in the console. Use on
  /pr-draft, "draft a PR", "write the PR description", "open a PR".
---

# PR draft

The draft is a save, never a post: `mcp__repo__draft_pr` writes it, the console
opens it, and the user edits each section and creates the PR there.

## 1. Find the template

Look for the first of these that exists, from the repo root:

```
ls .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md \
  docs/pull_request_template.md pull_request_template.md \
  .github/PULL_REQUEST_TEMPLATE/*.md 2>/dev/null
```

Several files in `.github/PULL_REQUEST_TEMPLATE/`: ask the user which one. No
template: use the sections Summary, Changes and Testing.

Done when you have read the template and listed its headings in order.

## 2. Pick the base and head

`mcp__repo__git_status` gives the head branch. The base is the default branch:
`git symbolic-ref --short refs/remotes/origin/HEAD`, minus `origin/`, else
`main`. A head that equals the base means there is nothing to draft: say so and
stop.

Done when you know both branch names.

## 3. Read the change

- `mcp__repo__git_log` with `rev: BASE..HEAD`: every commit.
- `mcp__repo__git_diff` with `base: BASE` and `stat: true`: every changed file.
- `mcp__repo__git_diff` with `base` and `paths`: the diff, a few files at a
  time.

Done when every changed file is accounted for: you can say in one line why it
changed.

## 4. Fill every section

One section per template heading, in template order, heading text without `#`:

- Write from the diff and the commits, in plain markdown. Name files and
  behaviour, not your process.
- Keep the template's checklists; tick a box (`- [x]`) only when the diff shows
  it is true.
- Keep the template's own prompts out of the body (HTML comments, "Describe your
  change").
- A heading the change does not touch gets the body `N/A`.

The title is one line in the project's commit style (look at `git_log` subjects,
e.g. `feat: ...`).

Done when every heading has a body.

## 5. Save

Call `mcp__repo__draft_pr` with `title`, `base` and `sections`
(`[{heading, body}]`). A refusal names the bad field: fix that field and call
again. Reply in one line that the draft is saved, with its id. The page opens on
its own: share no console link. If the user says it did not open, call
`mcp__repo__draft_open` with the id.

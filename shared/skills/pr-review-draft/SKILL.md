---
name: pr-review-draft
description:
  Review a GitHub pull request and draft the review in Conventional Comments,
  saved for the user to edit and post in the console. Use on /pr-review-draft N,
  "review PR N", "draft a review".
---

# PR review draft

The draft is a save, never a post: `mcp__repo__draft_review` writes it, the
console opens it, and the user edits each comment and posts the review there. No
PR number in the arguments: ask for one.

## 1. Read the intent

`mcp__repo__pr_view` with `number`: title, body, linked issues, files, earlier
reviews. `mcp__repo__pr_checks`: CI state.

Done when you can say in one sentence what the PR claims to do.

## 2. Read the diff

`mcp__repo__pr_diff` with `name_only: true` lists the files. Read the diff file
by file (`mcp__repo__pr_diff`; for the code around a hunk, `Read` the file in
the checkout). Check each file against the intent: correctness, edge cases,
error paths, tests that prove the change, security, names.

Done when every changed file is accounted for: a finding, or a reason it is
fine.

## 3. Write the comments

Each comment is one finding in Conventional Comments:

| label        | use for                                      |
| ------------ | -------------------------------------------- |
| `issue`      | a defect; say what breaks and when           |
| `suggestion` | a better way, with the change spelled out    |
| `question`   | something you could not settle from the code |
| `nitpick`    | style or naming, never blocking              |
| `praise`     | something done well, specific                |
| `todo`       | a small required follow-up                   |
| `chore`      | process work: changelog, docs, version bump  |
| `thought`    | an idea for later, never blocking            |

Decorations: `blocking` (must change before merge), `non-blocking`, `if-minor`,
`security`, `test`.

- Give `path` (repo-relative) and `line` (in the PR's new version) when one line
  is the cause; leave both out for a comment about the whole change.
- The body says what and why in a few sentences of markdown; a `suggestion`
  shows the code.
- At most 12 comments besides nitpicks; keep the ones that matter most.
- An unsure finding is a `question`, not an `issue`.

Done when every finding from step 2 is a comment or deliberately dropped.

## 4. Pick the event and summary

- `REQUEST_CHANGES` when any comment is `blocking`.
- `APPROVE` when nothing blocks and CI passes.
- `COMMENT` otherwise.

The summary is two to four sentences: what the PR does, the verdict, and the
main reason.

## 5. Save

Call `mcp__repo__draft_review` with `pr`, `event`, `summary` and `comments`
(`[{label, decorations, path, line, body}]`). A refusal names the bad field: fix
that field and call again. Reply in one line that the draft is saved, with its
id. The page opens on its own: share no console link. If the user says it did
not open, call `mcp__repo__draft_open` with the id.

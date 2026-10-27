---
name: handoff
description:
  Save where this session stopped, or pick up where an earlier session stopped,
  through notes in the repo's .git/handoff folder. Use on /handoff, /handoff
  save, "hand off", "write a handoff", "pick up where we left off", "continue
  from last session", "resume the previous work".
---

# Handoff

Notes live in the repo's git dir, so they are never committed:

```
notes="$(git rev-parse --path-format=absolute --git-common-dir)/handoff"
```

Outside a git repo, say that handoff needs one and stop.

Pick the mode from the arguments:

- `save` or `save TOPIC`, or the user is wrapping up: **Save**.
- Nothing, or a `TOPIC`: **Resume**.

## Save

1. Gather, with bounded output:

   ```
   git branch --show-current
   git rev-parse --short HEAD
   git status --short | head -40
   git log --oneline -10
   ```

2. Write `$notes/<YYYY-MM-DD-HHMM>-<topic-slug>.md` (create the folder). The
   topic is the argument, or a 2-4 word name for the work. Use these sections
   and drop none:

   ```
   # <Topic>

   Branch: <branch> at <short sha>

   ## Goal
   What the user asked for, in one or two sentences.

   ## Done
   What was built or changed, with commit shas.

   ## In progress
   Uncommitted files and what each change is for.

   ## Decisions
   Choices made and why, including what the user ruled out.

   ## Open problems
   Failing tests, errors and unanswered questions, as they really are. "None" if none.

   ## Next step
   One concrete command or edit to start with.
   ```

   Write only what happened in this session. Never claim a test passed if it did
   not run.

3. Print the note's path.

## Resume

1. List the notes: `ls -t "$notes" 2>/dev/null | head -5`. With a topic, take
   the newest name that contains it; otherwise the newest. With no notes, say
   so, show `git status --short | head -20` and `git log --oneline -5`, and ask
   what to work on.
2. Read the note.
3. Compare it with the repo now:

   ```
   git branch --show-current
   git log --oneline <note sha>..HEAD | head -20
   git status --short | head -40
   ```

4. Report in a few lines: the goal, the next step, and anything that changed
   since the note (new commits, another branch, files no longer modified). If
   the note's next step no longer fits, say why and suggest one that does.
5. Start on the next step unless the user asked only to see the note.

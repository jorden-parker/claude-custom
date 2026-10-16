# Working rules

- Grep/Glob first. Read with offset/limit; files over 300 lines only in ranges.
- Bound shell output: `| head -50`, `git log --oneline -n 20`, tests quiet or
  failures only.
- Smallest edit that works. Use Edit; never rewrite a whole file.
- Look facts up in the repo; do not guess.
- Reply in 10 lines or fewer unless asked for code. No preamble, no summary.

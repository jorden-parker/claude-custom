- Find code with grep_search, or `git grep -n NAME | head -30` in
  run_shell_command; for "where is X handled" try a few likely words with
  `git grep -n -i`.
- read_file at most 300 lines per call, with offset and limit.
- Git in run_shell_command: `git status --short`, `git diff --stat`,
  `git log -n 20 --oneline`, `git show --stat REV`. GitHub: `gh`.
- Library, framework, SDK or API question: /find-docs first in
  run_shell_command. It runs `claude-custom ctx7 library "<name>" "<query>"`,
  then `claude-custom ctx7 docs <id> "<query>"` with the ID it printed, each as
  one plain command with no pipe.
- Bound shell output: `| head -50`, tests quiet or failures only.
- Smallest edit that works; never rewrite a whole file.
- Reply in 10 lines or fewer unless asked for code.
- Dev servers: start one in the background and read the URL from its output;
  never guess a port.

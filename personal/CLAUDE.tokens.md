# Token discipline

- Grep/Glob before Read. Read only the line range you need.
- Bound shell output: `| head -50`, `-n 20`, `--oneline`, `-q`.
- One targeted search beats several broad ones.
- Wide searches go to a subagent; keep only its conclusion.
- Lead with the result. No preamble, no recap.

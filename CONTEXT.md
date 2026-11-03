# claude-custom

Overlays and a work harness that run Claude Code against a local Ollama model,
keeping a long session alive by restarting `claude` in place instead of letting
it compact.

## Language

### Session control

**Relaunch dir**: The per-launch folder through which other processes ask the
launcher to restart or degrade the running `claude` session. It lives as long as
one launcher process. _Avoid_: sentinel dir, session control dir, mailbox

**Signal file**: One named entry in the relaunch dir. A one-shot request
(`relaunch`, `ladder`, `ladder-up`) is consumed by the launcher when it acts on
it. A standing flag (`embed-off`, `heartbeat-fast`) stays in effect while it
exists. _Avoid_: sentinel, marker

**Rung**: One step down the degrade ladder (`embeddings-off`, `heartbeat`,
`context-down`) that the session runs on to survive memory pressure. Promoting a
rung means returning to the step above it. _Avoid_: level, mode

### Incidents

**Incident**: One recorded moment the session lost or changed context, named by
its cause: `aborted` (a request was dropped), `evicted` (the model was unloaded
or reloaded), `truncated` (the prompt overflowed the context), `reprefilled`
(the prompt cache was lost and the whole prompt ran again), `compacted` (Claude
Code summarised the conversation), `relaunched` (the session restarted from a
handoff), `degraded` (a rung fired), `recovered` (a rung was promoted back up)
or `unknown` (a log line about the model that fits no rule). _Avoid_: event,
error

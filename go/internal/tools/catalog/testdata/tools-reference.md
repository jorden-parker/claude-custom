> ## Documentation Index
> Fetch the complete documentation index at: https://code.claude.com/docs/llms.txt
> Use this file to discover all available pages before exploring further.

# Tools reference

> Complete reference for the tools Claude Code can use, including permission requirements and per-tool behavior.

Claude Code has access to a set of built-in tools that help it understand and modify your codebase. The tool names are the exact strings you use in [permission rules](/docs/en/permissions#tool-specific-permission-rules), [subagent tool lists](/docs/en/sub-agents), and [hook matchers](/docs/en/hooks).

To control which tools Claude can use and when it asks first, configure [permission rules](/docs/en/permissions#tool-specific-permission-rules) in your settings, [hooks](/docs/en/hooks), or a [subagent's tool list](/docs/en/sub-agents#supported-frontmatter-fields). See [Configure tools with permission rules and hooks](#configure-tools-with-permission-rules-and-hooks) for each place that accepts a tool name.

To add custom tools, connect an [MCP server](/docs/en/mcp). To extend Claude with reusable prompt-based workflows, write a [skill](/docs/en/skills), which runs through the existing `Skill` tool rather than adding a new tool entry.

<Info>
  In [auto mode](/docs/en/permission-modes#eliminate-prompts-with-auto-mode), a classifier decides most permission prompts instead of you. The `Permission required` column shows whether the tool prompts in [Manual mode](/docs/en/permission-modes) for paths inside the working directory. File-access tools marked No, including `Read`, `Grep`, and `Glob`, still prompt for paths outside the [working directory and additional directories](/docs/en/permissions#working-directories). `Bash` is marked Yes but runs a built-in set of [read-only commands](/docs/en/permissions#read-only-commands) without prompting.
</Info>

| Tool | Description | Permission required |
| :- | :- | :- |
| `Agent` | Spawns a [subagent](/docs/en/sub-agents) with its own context window to handle a task. With [agent teams](/docs/en/agent-teams) enabled, a call that carries a `name` can launch a [teammate](/docs/en/agent-teams#how-claude-starts-agent-teams) instead. See [Agent tool behavior](#agent-tool-behavior) | No |
| `Bash` | Executes shell commands in your environment. See [Bash tool behavior](#bash-tool-behavior) | Yes |
| `TaskOutput` | Removed in v2.1.277. Previously retrieved output from a background task; Claude reads a background task's [output file](/docs/en/interactive-mode#how-backgrounding-works) with `Read` instead | No |
| `TodoWrite` | Manages the session task checklist. Disabled by default in favor of `TaskCreate`, `TaskGet`, `TaskList`, and `TaskUpdate`. Set `CLAUDE_CODE_ENABLE_TASKS=0` to re-enable it in [sessions that have the task-tracking tools](#task-tool-availability) | No |
| `WebSearch` | Performs web searches. See [WebSearch tool behavior](#websearch-tool-behavior) | Yes |

## Configure tools with permission rules and hooks

For the most part, Claude decides when to use these tools and you don't need to name them yourself when interacting with Claude. You reference tool names directly when defining permissions and other configuration:

* in [`permissions.allow`](/docs/en/settings-reference#permissions-allow) and [`permissions.deny`](/docs/en/settings-reference#permissions-deny) in settings, and the `/permissions` interface
* in the `--allowedTools` and `--disallowedTools` [CLI flags](/docs/en/cli-reference)
* in the Agent SDK's [`allowedTools` and `disallowedTools`](/docs/en/agent-sdk/permissions#allow-and-deny-rules) options
* in a [skill's `allowed-tools`](/docs/en/skills#frontmatter-reference) frontmatter
* in a hook's [`if` condition](/docs/en/hooks-guide#filter-by-tool-name-and-arguments-with-the-if-field)

All of these accept the same rule format, `ToolName(specifier)`. The specifier depends on the tool, and several tools share a format:

| Rule format | Applies to | Details |
| :- | :- | :- |
| `Bash(npm run *)` | Bash, Monitor | [Command pattern matching](/docs/en/permissions#bash) |

import { describe, expect, it } from "vitest";
import { hookLines, settingsPathFor } from "./profile-base";

describe("settingsPathFor", () => {
  it("uses the personal overlay for claude-code and the size profile for Ollama", () => {
    expect(settingsPathFor("/repo", "claude-code")).toBe("/repo/personal/settings.tokens.json");
    expect(settingsPathFor("/repo", "ollama-27b")).toBe("/repo/ollama/settings.27b.json");
    expect(settingsPathFor("/repo", "ollama-3b")).toBe("/repo/ollama/settings.3b.json");
  });
});

describe("hookLines", () => {
  it("lists each hook's event, matcher and script name", () => {
    const settings = {
      hooks: {
        PreToolUse: [
          {
            matcher: "Bash",
            hooks: [
              { type: "command", command: '"$CLAUDE_CUSTOM_HOME"/shared/host-env "$CLAUDE_CUSTOM_HOME"/shared/hooks/bash-output-guard.py' },
            ],
          },
        ],
        Stop: [{ hooks: [{ type: "command", command: '"$CLAUDE_CUSTOM_HOME"/shared/hooks/stop-verify.py' }] }],
      },
    };

    expect(hookLines(settings)).toEqual([
      { event: "PreToolUse", matcher: "Bash", command: "bash-output-guard.py" },
      { event: "Stop", matcher: "*", command: "stop-verify.py" },
    ]);
  });

  it("returns nothing when the settings have no hooks", () => {
    expect(hookLines({})).toEqual([]);
    expect(hookLines(null)).toEqual([]);
  });
});

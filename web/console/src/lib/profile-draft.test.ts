import { describe, expect, it } from "vitest";
import {
  withContext,
  withEnv,
  withOutputTokens,
  withParameter,
  withSandbox,
  withThinking,
  withToolState,
} from "./profile-draft";

describe("profile drafts", () => {
  it("sets a tool state and drops the entry when it goes back to default", () => {
    const set = withToolState({}, "WebFetch", "deny");
    expect(set).toEqual({ tools: { WebFetch: "deny" } });
    expect(withToolState(set, "WebFetch", "default")).toEqual({});
  });

  it("keeps other tools when one changes", () => {
    const draft = withToolState(withToolState({}, "Bash", "ask"), "WebFetch", "off");
    expect(withToolState(draft, "Bash", "default")).toEqual({ tools: { WebFetch: "off" } });
  });

  it("sets and clears a parameter", () => {
    const set = withParameter({}, "temperature", 0.6);
    expect(set).toEqual({ parameters: { temperature: 0.6 } });
    expect(withParameter(set, "temperature", null)).toEqual({});
  });

  it("sets and clears the output tokens", () => {
    expect(withOutputTokens({}, 4096)).toEqual({ output_tokens: 4096 });
    expect(withOutputTokens({ output_tokens: 4096 }, null)).toEqual({ output_tokens: undefined });
  });

  it("sets and clears context and sandbox", () => {
    expect(withContext({}, 32768)).toEqual({ context: 32768 });
    expect(withContext({ context: 32768 }, null)).toEqual({ context: undefined });
    expect(withSandbox({}, false)).toEqual({ sandbox: false });
  });

  it("sets and clears thinking", () => {
    expect(withThinking({}, true)).toEqual({ thinking: true });
    expect(withThinking({ thinking: true }, null)).toEqual({ thinking: undefined });
  });

  it("sets and clears an env key", () => {
    expect(withEnv({}, "CLAUDE_OLLAMA_CMUX", "0")).toEqual({ env: { CLAUDE_OLLAMA_CMUX: "0" } });
    expect(withEnv({ env: { CLAUDE_OLLAMA_CMUX: "0" } }, "CLAUDE_OLLAMA_CMUX", null)).toEqual({});
  });
});

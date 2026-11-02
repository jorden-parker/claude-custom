import { describe, expect, it } from "vitest";
import {
  CONTEXT_CAP,
  overrideCount,
  validateProfileOverride,
  type ProfileRules,
} from "./profile-rules";

const OLLAMA: ProfileRules = {
  kind: "ollama",
  toolNames: ["Bash", "WebFetch", "Agent"],
  contextMaximum: CONTEXT_CAP,
};

const CLAUDE_CODE: ProfileRules = {
  kind: "claude-code",
  toolNames: ["Bash", "WebFetch"],
  contextMaximum: CONTEXT_CAP,
};

function accepted(body: unknown, rules: ProfileRules) {
  const result = validateProfileOverride(body, rules);
  if (!result.ok) {
    throw new Error(`expected ok, got: ${result.message}`);
  }
  return result.override;
}

function rejected(body: unknown, rules: ProfileRules): string {
  const result = validateProfileOverride(body, rules);
  if (result.ok) {
    throw new Error("expected a rejection");
  }
  return result.message;
}

describe("validateProfileOverride", () => {
  it("accepts an empty override", () => {
    expect(accepted({}, OLLAMA)).toEqual({});
  });

  it("drops tool entries that are default and empty sections", () => {
    expect(accepted({ tools: { Bash: "default" }, env: {} }, CLAUDE_CODE)).toEqual({});
  });

  it("keeps tool states from the enum, including off", () => {
    expect(accepted({ tools: { Bash: "ask", WebFetch: "off" } }, CLAUDE_CODE)).toEqual({
      tools: { Bash: "ask", WebFetch: "off" },
    });
  });

  it("rejects a tool that is not in the catalog", () => {
    expect(rejected({ tools: { Nope: "allow" } }, CLAUDE_CODE)).toBe("unknown tool Nope");
  });

  it("rejects a tool state outside the enum", () => {
    expect(rejected({ tools: { Bash: "maybe" } }, CLAUDE_CODE)).toBe("Bash must be one of default, allow, ask, deny, off");
  });

  it("keeps Agent off for Ollama profiles", () => {
    expect(rejected({ tools: { Agent: "allow" } }, OLLAMA)).toBe("Agent stays off for Ollama profiles");
    expect(accepted({ tools: { Agent: "off" } }, OLLAMA)).toEqual({ tools: { Agent: "off" } });
  });

  it("refuses sandbox on Ollama profiles and accepts a boolean for claude-code", () => {
    expect(rejected({ sandbox: false }, OLLAMA)).toBe("sandbox is always on for Ollama profiles");
    expect(accepted({ sandbox: false }, CLAUDE_CODE)).toEqual({ sandbox: false });
    expect(rejected({ sandbox: "no" }, CLAUDE_CODE)).toBe("sandbox must be true or false");
  });

  it("refuses context and parameters on claude-code profiles", () => {
    expect(rejected({ context: 65536 }, CLAUDE_CODE)).toBe("context only applies to Ollama profiles");
  });

  it("keeps context between 4096 and the maximum", () => {
    expect(accepted({ context: 4096 }, OLLAMA)).toEqual({ context: 4096 });
    expect(rejected({ context: 4095 }, OLLAMA)).toBe("context must be from 4096 to 262144");
    expect(rejected({ context: CONTEXT_CAP + 1 }, OLLAMA)).toBe("context must be from 4096 to 262144");
    expect(rejected({ context: 8192.5 }, OLLAMA)).toBe("context must be from 4096 to 262144");
  });

  it("limits context to the base model maximum when it is lower", () => {
    const rules = { ...OLLAMA, contextMaximum: 98304 };
    expect(rejected({ context: 131072 }, rules)).toBe("context must be from 4096 to 98304");
  });

  it("accepts only allowlisted parameters inside their ranges", () => {
    expect(accepted({ parameters: { temperature: 0.6, top_k: 20 } }, OLLAMA)).toEqual({
      parameters: { temperature: 0.6, top_k: 20 },
    });
    expect(rejected({ parameters: { seed: 1 } }, OLLAMA)).toBe("unknown parameter seed");
    expect(rejected({ parameters: { temperature: 3 } }, OLLAMA)).toBe("temperature must be from 0 to 2");
    expect(rejected({ parameters: { top_p: 1.5 } }, OLLAMA)).toBe("top_p must be from 0 to 1");
    expect(rejected({ parameters: { top_k: 2.5 } }, OLLAMA)).toBe("top_k must be a whole number");
  });

  it("accepts MCP toggles only for the three launcher servers on Ollama", () => {
    expect(accepted({ mcp: { dev: false, repo: true } }, OLLAMA)).toEqual({ mcp: { dev: false, repo: true } });
    expect(rejected({ mcp: { github: true } }, OLLAMA)).toBe("unknown MCP server github");
    expect(rejected({ mcp: { dev: true } }, CLAUDE_CODE)).toBe("mcp only applies to Ollama profiles");
    expect(rejected({ mcp: { dev: "yes" } }, OLLAMA)).toBe("dev must be true or false");
  });

  it("allows only the four launcher env keys with 0 or 1", () => {
    expect(accepted({ env: { CLAUDE_OLLAMA_TELEMETRY: "0" } }, OLLAMA)).toEqual({
      env: { CLAUDE_OLLAMA_TELEMETRY: "0" },
    });
    expect(rejected({ env: { PATH: "/tmp" } }, OLLAMA)).toBe("unknown env key PATH");
    expect(rejected({ env: { CLAUDE_OLLAMA_CMUX: "off" } }, OLLAMA)).toBe("CLAUDE_OLLAMA_CMUX must be 0 or 1");
  });

  it("rejects keys it does not know and non-object bodies", () => {
    expect(rejected({ hooks: {} }, OLLAMA)).toBe("unknown key hooks");
    expect(rejected(null, OLLAMA)).toBe("Expected a profile object");
    expect(rejected([], OLLAMA)).toBe("Expected a profile object");
  });
});

describe("overrideCount", () => {
  it("counts each tool, each scalar and each map entry", () => {
    expect(overrideCount({})).toBe(0);
    expect(
      overrideCount({
        tools: { Bash: "ask", WebFetch: "off" },
        sandbox: false,
        context: 65536,
        parameters: { temperature: 0.6 },
        mcp: { dev: false },
        env: { CLAUDE_OLLAMA_CMUX: "0" },
      }),
    ).toBe(7);
  });
});

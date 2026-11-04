import { describe, expect, it } from "vitest";
import {
  CONTEXT_CAP,
  OUTPUT_TOKENS_RANGE,
  PROFILE_ENV_FIELDS,
  PROFILE_ENV_GROUPS,
  PROFILE_ENV_KEYS,
  envFieldsByGroup,
  overrideCount,
  validateProfileOverride,
  type ProfileRules,
} from "./profile-rules";
import profileEnvCatalogue from "./profile-env.generated.json";

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
    expect(
      accepted({ tools: { Bash: "default" }, env: {} }, CLAUDE_CODE),
    ).toEqual({});
  });

  it("keeps tool states from the enum, including off", () => {
    expect(
      accepted({ tools: { Bash: "ask", WebFetch: "off" } }, CLAUDE_CODE),
    ).toEqual({
      tools: { Bash: "ask", WebFetch: "off" },
    });
  });

  it("rejects a tool that is not in the catalog", () => {
    expect(rejected({ tools: { Nope: "allow" } }, CLAUDE_CODE)).toBe(
      "unknown tool Nope",
    );
  });

  it("rejects a tool state outside the enum", () => {
    expect(rejected({ tools: { Bash: "maybe" } }, CLAUDE_CODE)).toBe(
      "Bash must be one of default, allow, ask, deny, off",
    );
  });

  it("keeps Agent off for Ollama profiles", () => {
    expect(rejected({ tools: { Agent: "allow" } }, OLLAMA)).toBe(
      "Agent stays off for Ollama profiles",
    );
    expect(accepted({ tools: { Agent: "off" } }, OLLAMA)).toEqual({
      tools: { Agent: "off" },
    });
  });

  it("refuses sandbox on Ollama profiles and accepts a boolean for claude-code", () => {
    expect(rejected({ sandbox: false }, OLLAMA)).toBe(
      "sandbox is always on for Ollama profiles",
    );
    expect(accepted({ sandbox: false }, CLAUDE_CODE)).toEqual({
      sandbox: false,
    });
    expect(rejected({ sandbox: "no" }, CLAUDE_CODE)).toBe(
      "sandbox must be true or false",
    );
  });

  it("refuses context and parameters on claude-code profiles", () => {
    expect(rejected({ context: 65536 }, CLAUDE_CODE)).toBe(
      "context only applies to Ollama profiles",
    );
    expect(rejected({ output_tokens: 4096 }, CLAUDE_CODE)).toBe(
      "output_tokens only applies to Ollama profiles",
    );
  });

  it("keeps output_tokens a whole number from 1024 to 16384", () => {
    expect(OUTPUT_TOKENS_RANGE).toEqual({ min: 1024, max: 16384, step: 1024 });
    expect(accepted({ output_tokens: 4096 }, OLLAMA)).toEqual({
      output_tokens: 4096,
    });
    expect(accepted({ output_tokens: 1024 }, OLLAMA)).toEqual({
      output_tokens: 1024,
    });
    expect(accepted({ output_tokens: 16384 }, OLLAMA)).toEqual({
      output_tokens: 16384,
    });
    const message = "output_tokens must be a whole number from 1024 to 16384";
    expect(rejected({ output_tokens: 1023 }, OLLAMA)).toBe(message);
    expect(rejected({ output_tokens: 16385 }, OLLAMA)).toBe(message);
    expect(rejected({ output_tokens: 2048.5 }, OLLAMA)).toBe(message);
    expect(rejected({ output_tokens: "4096" }, OLLAMA)).toBe(message);
  });

  it("keeps context between 4096 and the maximum", () => {
    expect(accepted({ context: 4096 }, OLLAMA)).toEqual({ context: 4096 });
    expect(rejected({ context: 4095 }, OLLAMA)).toBe(
      "context must be from 4096 to 262144",
    );
    expect(rejected({ context: CONTEXT_CAP + 1 }, OLLAMA)).toBe(
      "context must be from 4096 to 262144",
    );
    expect(rejected({ context: 8192.5 }, OLLAMA)).toBe(
      "context must be from 4096 to 262144",
    );
  });

  it("limits context to the base model maximum when it is lower", () => {
    const rules = { ...OLLAMA, contextMaximum: 98304 };
    expect(rejected({ context: 131072 }, rules)).toBe(
      "context must be from 4096 to 98304",
    );
  });

  it("accepts only allowlisted parameters inside their ranges", () => {
    expect(
      accepted({ parameters: { temperature: 0.6, top_k: 20 } }, OLLAMA),
    ).toEqual({
      parameters: { temperature: 0.6, top_k: 20 },
    });
    expect(rejected({ parameters: { seed: 1 } }, OLLAMA)).toBe(
      "unknown parameter seed",
    );
    expect(rejected({ parameters: { temperature: 3 } }, OLLAMA)).toBe(
      "temperature must be from 0 to 2",
    );
    expect(rejected({ parameters: { top_p: 1.5 } }, OLLAMA)).toBe(
      "top_p must be from 0 to 1",
    );
    expect(rejected({ parameters: { top_k: 2.5 } }, OLLAMA)).toBe(
      "top_k must be a whole number",
    );
  });

  it("accepts MCP toggles only for the three launcher servers on Ollama", () => {
    expect(accepted({ mcp: { dev: false, repo: true } }, OLLAMA)).toEqual({
      mcp: { dev: false, repo: true },
    });
    expect(rejected({ mcp: { github: true } }, OLLAMA)).toBe(
      "unknown MCP server github",
    );
    expect(rejected({ mcp: { dev: true } }, CLAUDE_CODE)).toBe(
      "mcp only applies to Ollama profiles",
    );
    expect(rejected({ mcp: { dev: "yes" } }, OLLAMA)).toBe(
      "dev must be true or false",
    );
  });

  it("accepts a boolean thinking switch for Ollama profiles only", () => {
    expect(accepted({ thinking: true }, OLLAMA)).toEqual({ thinking: true });
    expect(rejected({ thinking: "yes" }, OLLAMA)).toBe(
      "thinking must be true or false",
    );
    expect(rejected({ thinking: true }, CLAUDE_CODE)).toBe(
      "thinking only applies to Ollama profiles",
    );
  });

  it("allows only the launcher env switches with 0 or 1", () => {
    expect(accepted({ env: { CLAUDE_OLLAMA_TELEMETRY: "0" } }, OLLAMA)).toEqual(
      {
        env: { CLAUDE_OLLAMA_TELEMETRY: "0" },
      },
    );
    expect(
      accepted(
        { env: { CLAUDE_OLLAMA_RELAUNCH: "0", CLAUDE_OLLAMA_INCIDENTS: "1" } },
        OLLAMA,
      ),
    ).toEqual({
      env: { CLAUDE_OLLAMA_RELAUNCH: "0", CLAUDE_OLLAMA_INCIDENTS: "1" },
    });
    expect(rejected({ env: { PATH: "/tmp" } }, OLLAMA)).toBe(
      "unknown env key PATH",
    );
    expect(rejected({ env: { CLAUDE_OLLAMA_CMUX: "off" } }, OLLAMA)).toBe(
      "CLAUDE_OLLAMA_CMUX must be 0 or 1",
    );
    expect(rejected({ env: { CLAUDE_OLLAMA_RELAUNCH: "2" } }, OLLAMA)).toBe(
      "CLAUDE_OLLAMA_RELAUNCH must be 0 or 1",
    );
  });

  it("takes the handoff threshold as a whole percent from 30 to 85", () => {
    expect(
      accepted({ env: { CLAUDE_OLLAMA_HANDOFF_PCT: "60" } }, OLLAMA),
    ).toEqual({
      env: { CLAUDE_OLLAMA_HANDOFF_PCT: "60" },
    });
    const message =
      "CLAUDE_OLLAMA_HANDOFF_PCT must be a whole number from 30 to 85";
    for (const value of ["20", "90", "7.5", "abc", 60]) {
      expect(
        rejected({ env: { CLAUDE_OLLAMA_HANDOFF_PCT: value } }, OLLAMA),
      ).toBe(message);
    }
  });

  it("takes every env key, in order, from the rendered catalogue", () => {
    expect([...PROFILE_ENV_KEYS]).toEqual(
      profileEnvCatalogue.map((entry) => entry.key),
    );
    expect(
      PROFILE_ENV_FIELDS.map(({ label, help, group }) => ({
        label,
        help,
        group,
      })),
    ).toEqual(
      profileEnvCatalogue.map(({ label, help, group }) => ({
        label,
        help,
        group,
      })),
    );
  });

  it("lists a labelled field for every env key", () => {
    expect(PROFILE_ENV_FIELDS.map((field) => field.key)).toEqual([
      ...PROFILE_ENV_KEYS,
    ]);
    expect(PROFILE_ENV_FIELDS.every((field) => field.label !== field.key)).toBe(
      true,
    );
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_OLLAMA_HANDOFF_PCT",
      ),
    ).toMatchObject({
      kind: "number",
      range: { min: 30, max: 85, step: 5 },
      defaultValue: "70",
      ollamaOnly: true,
    });
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_OLLAMA_TELEMETRY",
      ),
    ).toMatchObject({
      kind: "switch",
      defaultValue: "0",
      ollamaOnly: false,
    });
  });

  it.each([
    ["CLAUDE_OLLAMA_PROXY", "1", "Prompt and context", true],
    ["CLAUDE_OLLAMA_RULE_CARDS", "1", "Prompt and context", true],
    ["CLAUDE_CUSTOM_FRICTION", "1", "Guards", false],
    ["CLAUDE_OLLAMA_LADDER", "1", "Guards", true],
    ["CLAUDE_OLLAMA_EDIT_NUDGE", "1", "Guards", true],
    ["CLAUDE_OLLAMA_LEASE", "1", "Model residency", true],
    ["CLAUDE_OLLAMA_FIT", "1", "Model residency", true],
    ["CLAUDE_OLLAMA_PROXY_STABILIZE", "0", "Prompt and context", true],
    ["CLAUDE_OLLAMA_PROXY_RECORD", "0", "Diagnostics", true],
    ["CLAUDE_OLLAMA_BEACON", "1", "Diagnostics", true],
  ])(
    "%s is a switch defaulting to %s under %s",
    (key, defaultValue, group, ollamaOnly) => {
      expect(
        PROFILE_ENV_FIELDS.find((field) => field.key === key),
      ).toMatchObject({
        kind: "switch",
        defaultValue,
        group,
        ollamaOnly,
      });
      expect(accepted({ env: { [key]: "0" } }, OLLAMA)).toEqual({
        env: { [key]: "0" },
      });
      expect(rejected({ env: { [key]: "yes" } }, OLLAMA)).toBe(
        `${key} must be 0 or 1`,
      );
    },
  );

  it("labels every switch in plain words", () => {
    const labelOf = (key: string) =>
      PROFILE_ENV_FIELDS.find((field) => field.key === key)?.label;
    expect(labelOf("CLAUDE_OLLAMA_PROXY")).toBe(
      "Observe prompt drift through the messages proxy",
    );
    expect(labelOf("CLAUDE_OLLAMA_PROXY_RECORD")).toBe(
      "Record every request body for replay benches",
    );
    expect(labelOf("CLAUDE_OLLAMA_PROXY_STABILIZE")).toBe(
      "Move volatile prompt lines after the stable prefix",
    );
    expect(labelOf("CLAUDE_CUSTOM_FRICTION")).toBe(
      "Reset a looping guard after three identical denials",
    );
    expect(labelOf("CLAUDE_OLLAMA_LADDER")).toBe(
      "Degrade rung by rung on incident evidence",
    );
    expect(labelOf("CLAUDE_OLLAMA_FIT")).toBe("Check memory fit before launch");
    expect(labelOf("CLAUDE_OLLAMA_BEACON")).toBe(
      "Write a machine beacon at launch",
    );
    expect(labelOf("CLAUDE_OLLAMA_RULE_CARDS")).toBe(
      "Deliver rule cards just in time",
    );
    expect(labelOf("CLAUDE_OLLAMA_EDIT_NUDGE")).toBe("Nudge wasteful edits");
  });

  it("takes the after-edit test mode as off, suggest or run", () => {
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
      ),
    ).toMatchObject({
      kind: "choice",
      choices: [
        { value: "0", word: "off" },
        { value: "suggest", word: "suggest" },
        { value: "run", word: "run" },
      ],
      defaultValue: "suggest",
      group: "Guards",
      ollamaOnly: true,
      label: "After each edit: suggest the test, or run it",
    });
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
      )?.help,
    ).toMatch(
      /under macOS Seatbelt with the same profile as claude-ollama qwen/,
    );
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
      )?.help,
    ).toMatch(/only suggests on other platforms/);
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
      )?.help,
    ).toMatch(/profile file the sandboxed session cannot write/);
    for (const value of ["0", "suggest", "run"]) {
      expect(
        accepted({ env: { CLAUDE_OLLAMA_TEST_AFTER_EDIT: value } }, OLLAMA),
      ).toEqual({
        env: { CLAUDE_OLLAMA_TEST_AFTER_EDIT: value },
      });
    }
    const message =
      "CLAUDE_OLLAMA_TEST_AFTER_EDIT must be one of 0, suggest, run";
    for (const value of ["1", "yes", "", 0]) {
      expect(
        rejected({ env: { CLAUDE_OLLAMA_TEST_AFTER_EDIT: value } }, OLLAMA),
      ).toBe(message);
    }
  });

  it("takes the thinking effort as low, medium or xhigh", () => {
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_CODE_EFFORT_LEVEL",
      ),
    ).toMatchObject({
      kind: "choice",
      choices: [
        { value: "low", word: "low" },
        { value: "medium", word: "medium" },
        { value: "xhigh", word: "xhigh" },
      ],
      defaultValue: "xhigh",
      group: "Prompt and context",
      ollamaOnly: true,
      label: "Thinking effort when thinking is on",
    });
    expect(
      PROFILE_ENV_FIELDS.find(
        (field) => field.key === "CLAUDE_CODE_EFFORT_LEVEL",
      )?.help,
    ).toMatch(/Qwen 3\.6 .*ignores it/);
    for (const value of ["low", "medium", "xhigh"]) {
      expect(
        accepted({ env: { CLAUDE_CODE_EFFORT_LEVEL: value } }, OLLAMA),
      ).toEqual({ env: { CLAUDE_CODE_EFFORT_LEVEL: value } });
    }
    const message =
      "CLAUDE_CODE_EFFORT_LEVEL must be one of low, medium, xhigh";
    for (const value of ["high", "max", "", 1]) {
      expect(
        rejected({ env: { CLAUDE_CODE_EFFORT_LEVEL: value } }, OLLAMA),
      ).toBe(message);
    }
  });

  it("keeps the Ollama-only switches off the claude-code profile", () => {
    expect(
      accepted({ env: { CLAUDE_CUSTOM_FRICTION: "0" } }, CLAUDE_CODE),
    ).toEqual({
      env: { CLAUDE_CUSTOM_FRICTION: "0" },
    });
    expect(rejected({ env: { CLAUDE_OLLAMA_LEASE: "0" } }, CLAUDE_CODE)).toBe(
      "CLAUDE_OLLAMA_LEASE only applies to Ollama profiles",
    );
  });

  it("groups every field under one of the page headings, in heading order", () => {
    expect(PROFILE_ENV_GROUPS).toEqual([
      "Prompt and context",
      "Guards",
      "Model residency",
      "Diagnostics",
      "Browser",
    ]);
    expect(
      PROFILE_ENV_FIELDS.every((field) =>
        PROFILE_ENV_GROUPS.includes(field.group),
      ),
    ).toBe(true);
    const grouped = envFieldsByGroup(PROFILE_ENV_FIELDS);
    expect(grouped.map(({ group }) => group)).toEqual([...PROFILE_ENV_GROUPS]);
    expect(
      grouped.flatMap(({ fields }) => fields.map((field) => field.key)),
    ).toEqual([...PROFILE_ENV_KEYS]);
    expect(
      grouped
        .find(({ group }) => group === "Guards")
        ?.fields.map((field) => field.key),
    ).toEqual([
      "CLAUDE_CUSTOM_FRICTION",
      "CLAUDE_OLLAMA_LADDER",
      "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
      "CLAUDE_OLLAMA_EDIT_NUDGE",
    ]);
    expect(envFieldsByGroup([]).length).toBe(0);
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
        output_tokens: 4096,
        thinking: true,
        parameters: { temperature: 0.6 },
        mcp: { dev: false },
        env: { CLAUDE_OLLAMA_CMUX: "0" },
      }),
    ).toBe(9);
  });
});

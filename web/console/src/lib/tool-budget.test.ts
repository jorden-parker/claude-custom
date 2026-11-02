import { describe, expect, it } from "vitest";
import {
  applySuggestion,
  budgetBars,
  parseToolBudgetReport,
  type ToolBudgetReport,
} from "./tool-budget";

const REPORT: ToolBudgetReport = {
  since_days: 14,
  requests: 26,
  rows: [
    {
      tool: "WebFetch",
      schema_bytes: 2048,
      requests: 26,
      session_bytes: 53248,
      calls: 0,
      bytes_per_call: null,
    },
    {
      tool: "Bash",
      schema_bytes: 1500,
      requests: 26,
      session_bytes: 39000,
      calls: 4,
      bytes_per_call: 9750,
    },
    {
      tool: "Grep",
      schema_bytes: 0,
      requests: 0,
      session_bytes: 0,
      calls: 1,
      bytes_per_call: 0,
    },
  ],
  protected: [
    "Bash",
    "Read",
    "Edit",
    "Write",
    "Skill",
    "mcp__code-search__semantic_search",
  ],
  protected_source: "built-in list in bin/tool-budget",
  suggest: { drop: ["WebFetch"], keep: ["Bash", "Grep"], saves_bytes: 2048 },
};

describe("parseToolBudgetReport", () => {
  it("reads the script's JSON", () => {
    expect(parseToolBudgetReport(JSON.stringify(REPORT))).toEqual(REPORT);
  });

  it("refuses text that is not a report", () => {
    expect(parseToolBudgetReport("not json")).toBeNull();
    expect(parseToolBudgetReport(JSON.stringify({ rows: "none" }))).toBeNull();
    expect(
      parseToolBudgetReport(
        JSON.stringify({ ...REPORT, suggest: { drop: "WebFetch" } }),
      ),
    ).toBeNull();
  });
});

describe("budgetBars", () => {
  it("scales each row's bytes per session against the largest", () => {
    expect(budgetBars(REPORT.rows).map((bar) => [bar.tool, bar.share])).toEqual(
      [
        ["WebFetch", 1],
        ["Bash", 39000 / 53248],
        ["Grep", 0],
      ],
    );
  });

  it("gives every row a zero bar when nothing was requested", () => {
    expect(budgetBars([REPORT.rows[2]])).toEqual([{ tool: "Grep", share: 0 }]);
  });
});

describe("applySuggestion", () => {
  const toolNames = ["Bash", "WebFetch", "WebSearch", "Read"];

  it("turns each suggested profile tool off and keeps the other overrides", () => {
    const applied = applySuggestion(
      { context: 32768, tools: { Read: "allow" } },
      ["WebFetch", "WebSearch"],
      toolNames,
    );

    expect(applied).toEqual({
      override: {
        context: 32768,
        tools: { Read: "allow", WebFetch: "off", WebSearch: "off" },
      },
      applied: ["WebFetch", "WebSearch"],
      skipped: [],
    });
  });

  it("skips a tool the profile does not list, such as an MCP tool", () => {
    const applied = applySuggestion(
      {},
      ["WebFetch", "mcp__repo__pr_view"],
      toolNames,
    );

    expect(applied.override).toEqual({ tools: { WebFetch: "off" } });
    expect(applied.applied).toEqual(["WebFetch"]);
    expect(applied.skipped).toEqual(["mcp__repo__pr_view"]);
  });

  it("skips a tool that is already off", () => {
    const applied = applySuggestion(
      { tools: { WebFetch: "off" } },
      ["WebFetch"],
      toolNames,
    );

    expect(applied.applied).toEqual([]);
    expect(applied.skipped).toEqual(["WebFetch"]);
  });
});

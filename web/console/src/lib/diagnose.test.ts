import { describe, expect, it } from "vitest";
import {
  parseRecipeEntries,
  parseRescueSummary,
  parseRuleCard,
  parseRuleCardList,
  parseWhyReport,
} from "./diagnose";

const WHY_JSON = [
  "{",
  ' "verdict": "evicted",',
  ' "summary": "the model left memory twice",',
  ' "evidence": "2 evicted rows, last 14:02:11; preceded by embed",',
  ' "fix": "models-max = 2 and CLAUDE_OLLAMA_LEASE=1",',
  ' "prefix": {"percent": 80, "stable": 8, "requests": 10},',
  ' "diverging": [{"section": "system", "count": 2}],',
  ' "incidents": {"evicted": 2, "aborted": 1},',
  ' "window": "last 120 minutes"',
  "}",
];

describe("parseWhyReport", () => {
  it("reads the why --json object out of the run lines", () => {
    expect(parseWhyReport(["warming up", ...WHY_JSON])).toEqual({
      verdict: "evicted",
      summary: "the model left memory twice",
      evidence: "2 evicted rows, last 14:02:11; preceded by embed",
      fix: "models-max = 2 and CLAUDE_OLLAMA_LEASE=1",
      prefix: { percent: 80, stable: 8, requests: 10 },
      diverging: [{ section: "system", count: 2 }],
      incidents: { evicted: 2, aborted: 1 },
      window: "last 120 minutes",
    });
  });

  it("returns null without a complete object", () => {
    expect(parseWhyReport([])).toBeNull();
    expect(parseWhyReport(["verdict: nothing wrong"])).toBeNull();
    expect(parseWhyReport(WHY_JSON.slice(0, 4))).toBeNull();
    expect(parseWhyReport(['{"verdict": "evicted"}'])).toBeNull();
  });
});

describe("parseRescueSummary", () => {
  it("reads the report path and the five summary lines", () => {
    expect(
      parseRescueSummary([
        "~/.claude-ollama/rescue/20261102T140211Z.md",
        "doctor: ok",
        "lease: no session holder",
        "incidents: 3 rows (evicted 2, aborted 1)",
        "proxy: 12 requests in last 120 min, prefix hit rate: 80%",
        "memory: 12 GiB free of 64 GiB",
      ]),
    ).toEqual({
      path: "~/.claude-ollama/rescue/20261102T140211Z.md",
      lines: [
        "doctor: ok",
        "lease: no session holder",
        "incidents: 3 rows (evicted 2, aborted 1)",
        "proxy: 12 requests in last 120 min, prefix hit rate: 80%",
        "memory: 12 GiB free of 64 GiB",
      ],
    });
  });

  it("returns null without a report path", () => {
    expect(parseRescueSummary([])).toBeNull();
    expect(parseRescueSummary(["rescue: cannot write /x"])).toBeNull();
  });
});

describe("parseRuleCardList", () => {
  it("reads one id and its triggers per line", () => {
    expect(
      parseRuleCardList("bash: tool Bash\ngo: suffix .go, command go test\n"),
    ).toEqual([
      { id: "bash", triggers: ["tool Bash"] },
      { id: "go", triggers: ["suffix .go", "command go test"] },
    ]);
  });

  it("skips lines without an id", () => {
    expect(parseRuleCardList("\nnot a card\n")).toEqual([]);
  });
});

describe("parseRuleCard", () => {
  it("splits the front matter triggers from the body", () => {
    const text = [
      "---",
      "triggers:",
      "  - suffix: .ts,.tsx",
      "  - path: web/console/",
      "---",
      "",
      "No raw colours in TS.",
      "Run vitest before you finish.",
      "",
    ].join("\n");
    expect(parseRuleCard("typescript", text)).toEqual({
      id: "typescript",
      triggers: ["suffix: .ts,.tsx", "path: web/console/"],
      body: "No raw colours in TS.\nRun vitest before you finish.",
    });
  });

  it("treats a file without front matter as all body", () => {
    expect(parseRuleCard("plain", "Just a line.\n")).toEqual({
      id: "plain",
      triggers: [],
      body: "Just a line.",
    });
  });
});

describe("parseRecipeEntries", () => {
  it("keeps every entry with a match and its steps", () => {
    expect(
      parseRecipeEntries(
        JSON.stringify([
          {
            match: "edit or add the test first",
            steps: ["edit the test", "run it"],
          },
          { match: 7, steps: ["skipped"] },
          { match: "no steps", steps: "retry" },
        ]),
      ),
    ).toEqual([
      {
        match: "edit or add the test first",
        steps: ["edit the test", "run it"],
      },
    ]);
  });

  it("returns an empty list for anything but a JSON array", () => {
    expect(parseRecipeEntries("{}")).toEqual([]);
    expect(parseRecipeEntries("not json")).toEqual([]);
  });
});

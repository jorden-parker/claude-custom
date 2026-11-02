import { describe, expect, it } from "vitest";
import {
  averagePromptBytes,
  latestLedger,
  ledgerTools,
  parseProxyRow,
  prefixHitRate,
  prefixSummary,
  proxyFrame,
  topDivergingSections,
} from "./proxy-log";

const first =
  '{"ts":"2026-11-02T14:02:00.000Z","request_id":"r0","sections":5,"stable_sections":0,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":3900,"ledger":{"system":900,"tools":{"read_file":300,"bash":1200},"messages":2600}}';
const systemDrift =
  '{"ts":"2026-11-02T14:04:00.000Z","request_id":"r2","sections":5,"stable_sections":0,"diverged_at":"system","offset":41,"diff":"Monday 2026-11-02.","prompt_bytes":4100,"ledger":{"system":900,"tools":{"read_file":300,"bash":1200},"messages":2800}}';
const messageDrift =
  '{"ts":"2026-11-02T14:03:00.000Z","request_id":"r1","sections":5,"stable_sections":4,"diverged_at":"message:4","offset":0,"diff":"{\\"content\\":\\"next\\"","prompt_bytes":4000,"ledger":{"system":900,"tools":{"read_file":300},"messages":2700}}';
const stable =
  '{"ts":"2026-11-02T14:05:00.000Z","request_id":"r3","sections":5,"stable_sections":5,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":4200}';

function rows(...lines: string[]) {
  return lines.map((line) => parseProxyRow(line)!);
}

describe("parseProxyRow", () => {
  it("reads a row with its ledger", () => {
    expect(parseProxyRow(systemDrift)).toEqual({
      ts: "2026-11-02T14:04:00.000Z",
      requestId: "r2",
      sections: 5,
      stableSections: 0,
      divergedAt: "system",
      offset: 41,
      diff: "Monday 2026-11-02.",
      promptBytes: 4100,
      ledger: {
        system: 900,
        tools: { read_file: 300, bash: 1200 },
        messages: 2800,
      },
    });
  });

  it("reads a row without a ledger", () => {
    expect(parseProxyRow(stable)?.ledger).toBeNull();
  });

  it("rejects rows that are not proxy rows", () => {
    expect(parseProxyRow("not json")).toBeNull();
    expect(parseProxyRow('{"cause":"aborted","ts":"t"}')).toBeNull();
  });
});

describe("prefixHitRate", () => {
  it("counts requests whose system and tools stayed stable, skipping the first", () => {
    expect(
      prefixHitRate(rows(first, messageDrift, systemDrift, stable)),
    ).toEqual({ stable: 2, requests: 3, percent: 67 });
  });

  it("is zero without requests", () => {
    expect(prefixHitRate([])).toEqual({ stable: 0, requests: 0, percent: 0 });
    expect(prefixSummary(prefixHitRate([]))).toBe(
      "0% of 0 requests stable through tools",
    );
  });
});

describe("averagePromptBytes", () => {
  it("averages the prompt sizes", () => {
    expect(averagePromptBytes(rows(first, systemDrift))).toBe(4000);
    expect(averagePromptBytes([])).toBe(0);
  });
});

describe("topDivergingSections", () => {
  it("lists the sections by count, system first on a tie", () => {
    expect(
      topDivergingSections(rows(first, messageDrift, systemDrift, stable)),
    ).toEqual([
      { section: "system", count: 1 },
      { section: "message:4", count: 1 },
    ]);
  });

  it("keeps at most three sections", () => {
    const many = rows(
      systemDrift,
      messageDrift,
      messageDrift.replace("message:4", "message:2"),
      messageDrift.replace("message:4", "tools"),
    );
    expect(topDivergingSections(many)).toHaveLength(3);
  });
});

describe("latestLedger", () => {
  it("takes the newest row that has a ledger", () => {
    expect(latestLedger(rows(first, systemDrift, stable))).toEqual({
      system: 900,
      tools: { read_file: 300, bash: 1200 },
      messages: 2800,
    });
    expect(latestLedger(rows(stable))).toBeNull();
  });

  it("sorts the tools by bytes with a share of the largest", () => {
    expect(ledgerTools(latestLedger(rows(systemDrift))!)).toEqual([
      { name: "bash", bytes: 1200, share: 1 },
      { name: "read_file", bytes: 300, share: 0.25 },
    ]);
  });
});

describe("proxyFrame", () => {
  it("shows where the request diverged and the diff", () => {
    const frame = proxyFrame(rows(systemDrift)[0]);
    expect(frame.text).toMatch(
      /^\d\d:\d\d:\d\d system · 41 · Monday 2026-11-02\.$/,
    );
    expect(frame.level).toBe("warn");
  });

  it("marks a stable request as debug and a message change as info", () => {
    expect(proxyFrame(rows(stable)[0]).level).toBe("debug");
    expect(proxyFrame(rows(stable)[0]).text).toMatch(/ stable · 5 sections$/);
    expect(proxyFrame(rows(messageDrift)[0]).level).toBe("info");
  });
});

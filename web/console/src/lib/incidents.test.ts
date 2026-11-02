import { describe, expect, it } from "vitest";
import {
  healthSummary,
  incidentCounts,
  incidentFrame,
  latestHealth,
  parseHealth,
  parseIncident,
} from "./incidents";

const aborted =
  '{"ts": "2026-11-02T14:01:30.100Z", "cause": "aborted", "detail": "error=\\"context canceled\\"", "tokens": null}';
const reprefilledAfterEmbed =
  '{"ts": "2026-11-02T14:04:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": {"kind": "embed", "ts": "2026-11-02T14:04:02Z"}}';
const health =
  '{"ts": "2026-11-02T14:05:00Z", "kind": "health", "rules": {"aborted/context-canceled": 1, "evicted/unload": 0}, "unmatched": 1, "lines": 36}';

describe("parseIncident", () => {
  it("reads the rule and the preceding event when the row has them", () => {
    expect(parseIncident(reprefilledAfterEmbed)).toEqual({
      ts: "2026-11-02T14:04:03.000Z",
      cause: "reprefilled",
      detail: "prompt eval time = 52000.00 ms / 65450 tokens",
      tokens: 65450,
      rule: "reprefilled/prompt-eval",
      precededBy: { kind: "embed", ts: "2026-11-02T14:04:02Z" },
    });
  });

  it("leaves out a null rule and a null preceding event", () => {
    expect(
      parseIncident(
        '{"ts": "t", "cause": "reprefilled", "detail": "d", "tokens": 5000, "rule": null, "preceded_by": null}',
      ),
    ).toEqual({ ts: "t", cause: "reprefilled", detail: "d", tokens: 5000 });
  });

  it("skips health rows", () => {
    expect(parseIncident(health)).toBeNull();
  });

  it("reads one incident line", () => {
    expect(parseIncident(aborted)).toEqual({
      ts: "2026-11-02T14:01:30.100Z",
      cause: "aborted",
      detail: 'error="context canceled"',
      tokens: null,
    });
  });

  it("files a cause it does not know under unknown", () => {
    expect(
      parseIncident(
        '{"ts": "t", "cause": "melted", "detail": "d", "tokens": 5}',
      ),
    ).toEqual({ ts: "t", cause: "unknown", detail: "d", tokens: 5 });
  });

  it("drops lines that are not incidents", () => {
    expect(parseIncident("not json")).toBeNull();
    expect(parseIncident('{"cause": "aborted"}')).toBeNull();
    expect(parseIncident("42")).toBeNull();
  });
});

describe("incidentCounts", () => {
  it("counts every cause, with zero for the ones not seen", () => {
    const incidents = [
      parseIncident(aborted)!,
      parseIncident(aborted)!,
      { ts: "t", cause: "evicted" as const, detail: "d", tokens: null },
    ];
    expect(incidentCounts(incidents)).toEqual({
      aborted: 2,
      evicted: 1,
      truncated: 0,
      reprefilled: 0,
      compacted: 0,
      relaunched: 0,
      unknown: 0,
    });
  });
});

describe("parseHealth", () => {
  it("reads one health row", () => {
    expect(parseHealth(health)).toEqual({
      ts: "2026-11-02T14:05:00Z",
      rules: { "aborted/context-canceled": 1, "evicted/unload": 0 },
      unmatched: 1,
      lines: 36,
    });
  });

  it("drops incidents and rows missing a count", () => {
    expect(parseHealth(aborted)).toBeNull();
    expect(
      parseHealth('{"kind": "health", "ts": "t", "rules": {}}'),
    ).toBeNull();
    expect(parseHealth("not json")).toBeNull();
  });
});

describe("latestHealth", () => {
  it("takes the newest health row among the lines", () => {
    const newer =
      '{"ts": "2026-11-02T14:06:00Z", "kind": "health", "rules": {}, "unmatched": 2, "lines": 40}';
    expect(latestHealth([health, aborted, newer])?.lines).toBe(40);
  });

  it("is null without a health row", () => {
    expect(latestHealth([aborted])).toBeNull();
  });
});

describe("healthSummary", () => {
  it("names the lines seen and the unmatched ones", () => {
    expect(healthSummary(parseHealth(health))).toBe(
      "saw 36 lines, 1 unmatched",
    );
  });

  it("says when no health row arrived yet", () => {
    expect(healthSummary(null)).toBe("no health row yet");
  });
});

describe("incidentFrame", () => {
  it("adds the preceding event and the rule as sub-labels", () => {
    const frame = incidentFrame(parseIncident(reprefilledAfterEmbed)!);
    expect(frame.text).toMatch(
      /^\d\d:\d\d:\d\d reprefilled · after embed · reprefilled\/prompt-eval prompt eval time = 52000\.00 ms \/ 65450 tokens \(65k tokens\)$/,
    );
  });

  it("shows the rule alone when no event preceded the incident", () => {
    const frame = incidentFrame({
      ts: "soon",
      cause: "aborted",
      detail: "d",
      tokens: null,
      rule: "aborted/context-canceled",
    });
    expect(frame.text).toBe("soon aborted · aborted/context-canceled d");
  });

  it("shows the clock, the cause, the detail and the token count", () => {
    const frame = incidentFrame({
      ts: "2026-11-02T14:02:40.000Z",
      cause: "reprefilled",
      detail: "prompt eval time = 9800.00 ms / 61234 tokens",
      tokens: 61234,
    });
    expect(frame.level).toBe("warn");
    expect(frame.text).toMatch(
      /^\d\d:\d\d:\d\d reprefilled prompt eval time = 9800\.00 ms \/ 61234 tokens \(61k tokens\)$/,
    );
  });

  it("shows a relaunch as information with the note it resumed from", () => {
    const line =
      '{"ts": "2026-11-02T14:07:00.000Z", "cause": "relaunched", "detail": "/repo/.git/handoff/2026-11-02-1406-tests.md", "tokens": 37806}';
    const frame = incidentFrame(parseIncident(line)!);
    expect(frame.level).toBe("info");
    expect(frame.text).toMatch(
      /^\d\d:\d\d:\d\d relaunched {2}\/repo\/\.git\/handoff\/2026-11-02-1406-tests\.md \(38k tokens\)$/,
    );
  });

  it("keeps an unreadable timestamp as it is", () => {
    const frame = incidentFrame({
      ts: "soon",
      cause: "compacted",
      detail: "d",
      tokens: null,
    });
    expect(frame.text).toBe("soon compacted   d");
    expect(frame.level).toBe("info");
  });
});

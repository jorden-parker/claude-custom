import { describe, expect, it } from "vitest";
import { incidentCounts, incidentFrame, parseIncident } from "./incidents";

const aborted =
  '{"ts": "2026-11-02T14:01:30.100Z", "cause": "aborted", "detail": "error=\\"context canceled\\"", "tokens": null}';

describe("parseIncident", () => {
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
      unknown: 0,
    });
  });
});

describe("incidentFrame", () => {
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

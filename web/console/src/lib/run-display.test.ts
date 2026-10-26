import { describe, expect, it } from "vitest";
import { elapsedSeconds, formatElapsed, reduceRunMessage, statusOf } from "./run-display";
import { initialRunState, type RunState } from "./run-state";

const endedOk: RunState = { ...initialRunState, ended: { code: 0, cancelled: false } };
const header = { command: "doctor", label: "Doctor (27b)", startedAt: "2026-10-26T10:00:00Z" };

describe("reduceRunMessage", () => {
  it("applies a parsed event with its id", () => {
    const next = reduceRunMessage(initialRunState, {
      data: JSON.stringify({ t: 1, kind: "line", stream: "stdout", text: "hi" }),
      lastEventId: "3",
    });
    expect(next.lines).toHaveLength(1);
    expect(next.lastEventId).toBe(3);
  });

  it("keeps the state for text that is not an event", () => {
    expect(reduceRunMessage(initialRunState, { data: "{", lastEventId: "1" })).toBe(initialRunState);
  });

  it("applies an event that carries no id", () => {
    const next = reduceRunMessage(initialRunState, {
      data: JSON.stringify({ t: 1, kind: "line", stream: "stdout", text: "hi" }),
      lastEventId: "",
    });
    expect(next.lines).toHaveLength(1);
  });
});

describe("statusOf", () => {
  it("maps the end event to a status", () => {
    expect(statusOf(endedOk, "running")).toBe("ok");
    expect(statusOf({ ...initialRunState, ended: { code: 2, cancelled: false } }, null)).toBe("failed");
    expect(statusOf({ ...initialRunState, ended: { code: -15, cancelled: true } }, null)).toBe("cancelled");
  });

  it("uses the server status until the end event arrives", () => {
    expect(statusOf(initialRunState, "lost")).toBe("lost");
    expect(statusOf(initialRunState, null)).toBe("running");
  });
});

describe("elapsedSeconds", () => {
  it("uses the last event time once the run has ended", () => {
    expect(elapsedSeconds({ ...endedOk, seconds: 9 }, 1)).toBe(9);
  });

  it("counts from the start time while running", () => {
    const running = { ...initialRunState, header, seconds: 1 };
    expect(elapsedSeconds(running, Date.parse("2026-10-26T10:00:30Z"))).toBe(30);
  });

  it("falls back to the event time before the clock ticks or without a valid start", () => {
    expect(elapsedSeconds({ ...initialRunState, header, seconds: 4 }, 0)).toBe(4);
    expect(elapsedSeconds({ ...initialRunState, header: { ...header, startedAt: "bad" }, seconds: 5 }, 99999)).toBe(5);
  });
});

describe("formatElapsed", () => {
  it("formats minutes and padded seconds", () => {
    expect(formatElapsed(0)).toBe("0:00");
    expect(formatElapsed(65.9)).toBe("1:05");
  });
});

import { describe, expect, it } from "vitest";
import type { RunEvent } from "./run-event";
import { applyRunEvent, initialRunState, MAX_LINES, type RunState } from "./run-state";

function line(text: string, stream = "stdout", t = 1): RunEvent {
  return { t, kind: "line", stream, text };
}

function apply(state: RunState, event: RunEvent, eventId?: number): RunState {
  return applyRunEvent(state, event, eventId);
}

describe("applyRunEvent", () => {
  it("records the start header", () => {
    const state = apply(initialRunState, {
      t: 0,
      kind: "start",
      command: "doctor",
      label: "Doctor (27b)",
      started_at: "2026-10-26T10:15:00Z",
    });
    expect(state.header).toEqual({ command: "doctor", label: "Doctor (27b)", startedAt: "2026-10-26T10:15:00Z" });
  });

  it("appends line events with their stream and time", () => {
    const state = [line("first"), line("oops", "stderr", 2)].reduce((state, event) => apply(state, event), initialRunState);
    expect(state.lines).toEqual([
      { stream: "stdout", text: "first", t: 1 },
      { stream: "stderr", text: "oops", t: 2 },
    ]);
  });

  it("replaces progress per stream", () => {
    const state = [
      { t: 1, kind: "progress", stream: "stderr", text: "pulling 10%" },
      { t: 2, kind: "progress", stream: "stderr", text: "pulling 50%" },
    ].reduce((state, event) => apply(state, event), initialRunState);
    expect(state.progress).toEqual({ stderr: "pulling 50%" });
    expect(state.lines).toEqual([]);
  });

  it("parses a stage from a [n/total] line", () => {
    const state = apply(initialRunState, line("[3/6] Thinking check"));
    expect(state.stage).toEqual({ number: 3, total: 6, title: "Thinking check" });
    expect(state.lines).toHaveLength(1);
  });

  it("leaves the stage alone for an ordinary line", () => {
    const state = apply(apply(initialRunState, line("[2/6] Power")), line("plain"));
    expect(state.stage).toEqual({ number: 2, total: 6, title: "Power" });
  });

  it("records the end and clears progress", () => {
    const withProgress = apply(initialRunState, { t: 1, kind: "progress", stream: "stdout", text: "50%" });
    const state = apply(withProgress, { t: 5, kind: "end", code: 1, cancelled: false });
    expect(state.ended).toEqual({ code: 1, cancelled: false });
    expect(state.progress).toEqual({});
  });

  it("ignores an event id it has already applied", () => {
    const once = apply(initialRunState, line("only once"), 4);
    const twice = apply(once, line("only once"), 4);
    expect(twice.lines).toHaveLength(1);
    expect(twice.lastEventId).toBe(4);
  });

  it("keeps at most MAX_LINES lines, dropping the oldest", () => {
    let state = initialRunState;
    for (let index = 0; index < MAX_LINES + 3; index += 1) {
      state = apply(state, line(`row ${index}`));
    }
    expect(state.lines).toHaveLength(MAX_LINES);
    expect(state.lines[0].text).toBe("row 3");
    expect(state.lines.at(-1)?.text).toBe(`row ${MAX_LINES + 2}`);
  });

  it("keeps the latest time seen", () => {
    const state = [line("a", "stdout", 4), line("b", "stdout", 2)].reduce((state, event) => apply(state, event), initialRunState);
    expect(state.seconds).toBe(4);
  });
});

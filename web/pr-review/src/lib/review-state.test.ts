import { describe, expect, it } from "vitest";
import {
  applyEvent,
  displayFileState,
  durationSeconds,
  fileFindingCount,
  fileOutcomeText,
  initialReviewState,
  isFileOpenByDefault,
  reduceEvents,
} from "./review-state";
import type { ReviewEvent } from "./review-event";

const events: ReviewEvent[] = [
  { kind: "start", name: "PR #7", title: "Fix parser", model: "qwen", base_url: "http://localhost:11434" },
  { kind: "stage", message: "fetching diff", t: 1 },
  { kind: "file_start", index: 1, total: 2, path: "src/a.ts", chars: 120 },
  { kind: "waiting", seconds: 3 },
  { kind: "writing", index: 1, path: "src/a.ts", chars: 400 },
  { kind: "retry", index: 1, path: "src/a.ts", reply: "not json" },
  {
    kind: "finding",
    index: 1,
    path: "src/a.ts",
    finding: { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary: "Null deref", why: "x can be null", confidence: "high" },
  },
  { kind: "check", index: 1, path: "src/a.ts", count: 2, kept: 1 },
  { kind: "file_done", index: 1, total: 2, path: "src/a.ts", outcome: "1 finding", seconds: 9 },
  { kind: "file_start", index: 2, total: 2, path: "src/b.ts", chars: 50 },
  { kind: "future_kind", whatever: true },
  { kind: "summary", text: "Mostly fine." },
  { kind: "verdict", verdict: "APPROVE WITH COMMENTS", seconds: 12 },
  { kind: "report", markdown: "# Report" },
  { kind: "end", status: "ok" },
];

describe("reduceEvents", () => {
  it("starts from an empty state", () => {
    expect(reduceEvents([])).toEqual(initialReviewState);
  });

  it("folds a complete review into header, stages, files and verdict", () => {
    const state = reduceEvents(events);

    expect(state.header).toEqual({ name: "PR #7", title: "Fix parser", model: "qwen", status: "ok" });
    expect(state.stages).toEqual([{ t: 1, message: "fetching diff" }]);
    expect(state.files).toHaveLength(2);
    expect(state.files[0]).toMatchObject({
      index: 1,
      path: "src/a.ts",
      state: "done",
      chars: 400,
      waitingSeconds: 3,
      outcome: "1 finding",
      seconds: 9,
      retries: ["not json"],
    });
    expect(state.files[0].findings).toEqual([
      { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary: "Null deref", why: "x can be null", confidence: "high" },
    ]);
    expect(state.files[1]).toMatchObject({ index: 2, path: "src/b.ts", state: "waiting", chars: 50 });
    expect(state.summary).toBe("Mostly fine.");
    expect(state.verdict).toEqual({ verdict: "APPROVE WITH COMMENTS", seconds: 12 });
    expect(state.report).toBe("# Report");
    expect(state.ended).toBe(true);
    expect(state.error).toBeNull();
  });

  it("ignores unknown kinds", () => {
    const withUnknown = reduceEvents([{ kind: "start", name: "x", title: "", model: "", base_url: "" }, { kind: "nope" }]);
    expect(withUnknown.header.name).toBe("x");
    expect(withUnknown.files).toEqual([]);
  });

  it("marks the run as running until end", () => {
    const state = reduceEvents(events.slice(0, 4));
    expect(state.header.status).toBe("running");
    expect(state.ended).toBe(false);
    expect(state.files[0].state).toBe("waiting");
  });

  it("records an error event and an error end status", () => {
    const state = reduceEvents([{ kind: "error", message: "model unreachable" }, { kind: "end", status: "error" }]);
    expect(state.error).toBe("model unreachable");
    expect(state.header.status).toBe("error");
  });

  it("keeps the latest event time as the elapsed seconds", () => {
    const state = reduceEvents([
      { kind: "start", t: 0, name: "x", title: "", model: "", base_url: "" },
      { kind: "file_start", t: 4, index: 1, total: 1, path: "a.ts", chars: 1 },
      { kind: "end", t: 79, status: "ok" },
    ]);
    expect(state.lastSeconds).toBe(79);
  });

  it("keeps the waiting seconds on the current file", () => {
    const state = reduceEvents([
      { kind: "file_start", t: 1, index: 1, total: 1, path: "a.ts", chars: 1 },
      { kind: "waiting", t: 13, seconds: 12 },
    ]);
    expect(state.files[0].waitingSeconds).toBe(12);
  });

  it("opens a file by default only while it runs or when it has findings", () => {
    const running = reduceEvents([{ kind: "file_start", index: 1, total: 1, path: "a.ts", chars: 1 }]);
    const doneClean = reduceEvents([
      { kind: "file_start", index: 1, total: 1, path: "a.ts", chars: 1 },
      { kind: "file_done", index: 1, total: 1, path: "a.ts", outcome: "clean", seconds: 2 },
    ]);
    const doneWithFinding = reduceEvents([
      { kind: "file_start", index: 1, total: 1, path: "a.ts", chars: 1 },
      { kind: "finding", index: 1, path: "a.ts", finding: { label: "issue", blocking: false, path: "a.ts", line: 1, summary: "s", why: "w", confidence: "high" } },
      { kind: "file_done", index: 1, total: 1, path: "a.ts", outcome: "1 finding", seconds: 2 },
    ]);

    expect(isFileOpenByDefault(running.files[0])).toBe(true);
    expect(isFileOpenByDefault(doneClean.files[0])).toBe(false);
    expect(isFileOpenByDefault(doneWithFinding.files[0])).toBe(true);
  });

  it("applies an event with a repeated id once", () => {
    const stage: ReviewEvent = { kind: "stage", t: 1, message: "fetching diff" };
    const once = applyEvent(initialReviewState, stage, 1);
    const replayed = applyEvent(once, stage, 1);

    expect(replayed.stages).toHaveLength(1);
  });

  it("applies events with no id on every call", () => {
    const stage: ReviewEvent = { kind: "stage", t: 1, message: "fetching diff" };
    const twice = applyEvent(applyEvent(initialReviewState, stage), stage);

    expect(twice.stages).toHaveLength(2);
  });

  describe("finding counts", () => {
    const start = { kind: "start", t: 0, name: "PR #3", title: "t", model: "m", base_url: "" };
    const fileStart = { kind: "file_start", t: 1, index: 1, total: 1, path: "src/a.ts", chars: 10 };
    const finding = (line: number): ReviewEvent => ({
      kind: "finding",
      t: 2,
      index: 1,
      path: "src/a.ts",
      finding: { label: "issue", blocking: false, path: "src/a.ts", line, summary: "s", why: "", confidence: "high" },
    });

    it("drops live findings when a retry arrives", () => {
      const state = reduceEvents([
        start,
        fileStart,
        { kind: "retry", t: 2, index: 1, path: "src/a.ts", reply: "not json" },
        finding(3),
        finding(4),
      ]);

      expect(state.files[0].findings).toHaveLength(2);
      expect(fileFindingCount(state.files[0])).toBe(2);
    });

    it("uses the count in file_done's outcome over the live findings", () => {
      const state = reduceEvents([
        start,
        fileStart,
        finding(3),
        finding(4),
        finding(5),
        finding(6),
        finding(7),
        finding(8),
        { kind: "file_done", t: 9, index: 1, total: 1, path: "src/a.ts", outcome: "5 findings", seconds: 3 },
      ]);

      expect(fileFindingCount(state.files[0])).toBe(5);
      expect(fileOutcomeText(state.files[0])).toBe("5 findings");
    });

    it("lets a check's kept count win over the outcome", () => {
      const state = reduceEvents([
        start,
        fileStart,
        finding(3),
        { kind: "check", t: 4, index: 1, path: "src/a.ts", count: 6, kept: 4 },
        { kind: "file_done", t: 5, index: 1, total: 1, path: "src/a.ts", outcome: "5 findings", seconds: 3 },
      ]);

      expect(fileFindingCount(state.files[0])).toBe(4);
      expect(fileOutcomeText(state.files[0])).toBe("4 findings");
    });

    it("counts a clean file as zero", () => {
      const state = reduceEvents([
        start,
        fileStart,
        { kind: "file_done", t: 2, index: 1, total: 1, path: "src/a.ts", outcome: "clean", seconds: 1 },
      ]);

      expect(fileFindingCount(state.files[0])).toBe(0);
      expect(fileOutcomeText(state.files[0])).toBe("clean");
    });

    it("falls back to live findings for a file without file_done", () => {
      const state = reduceEvents([start, fileStart, finding(3), finding(4)]);

      expect(fileFindingCount(state.files[0])).toBe(2);
    });
  });

  describe("displayFileState", () => {
    const runningFile = reduceEvents([
      { kind: "start", t: 0, name: "PR #3", title: "t", model: "m", base_url: "" },
      { kind: "file_start", t: 1, index: 1, total: 1, path: "src/a.ts", chars: 10 },
    ]).files[0];

    it("shows a running file as running while the review runs", () => {
      expect(displayFileState(runningFile, "running")).toBe("running");
    });

    it("shows a file still running when the review failed or stopped as stopped", () => {
      expect(displayFileState(runningFile, "error")).toBe("stopped");
      expect(displayFileState(runningFile, "stopped")).toBe("stopped");
    });

    it("shows a finished file as done", () => {
      const done = { ...runningFile, state: "done" as const };

      expect(displayFileState(done, "error")).toBe("done");
    });
  });

  it("uses the verdict's seconds for the duration, else the last event time", () => {
    const withVerdict = reduceEvents([
      { kind: "start", t: 0, name: "PR #3", title: "t", model: "m", base_url: "" },
      { kind: "verdict", t: 28, verdict: "APPROVE", seconds: 28 },
      { kind: "end", t: 30, status: "ok" },
    ]);
    const withoutVerdict = reduceEvents([
      { kind: "start", t: 0, name: "PR #3", title: "t", model: "m", base_url: "" },
      { kind: "end", t: 30, status: "ok" },
    ]);

    expect(durationSeconds(withVerdict)).toBe(28);
    expect(durationSeconds(withoutVerdict)).toBe(30);
  });
});

import { describe, expect, it } from "vitest";
import { initialReviewState, reduceEvents } from "./review-state";
import type { ReviewEvent } from "./review-event";

const events: ReviewEvent[] = [
  { kind: "start", name: "PR #7", title: "Fix parser", model: "qwen", base_url: "http://localhost:11434" },
  { kind: "stage", message: "fetching diff", t: 1 },
  { kind: "file_start", index: 1, total: 2, path: "src/a.ts", chars: 120 },
  { kind: "waiting", seconds: 3 },
  { kind: "writing", index: 1, path: "src/a.ts", chars: 400 },
  {
    kind: "finding",
    index: 1,
    path: "src/a.ts",
    finding: { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary: "Null deref", why: "x can be null", confidence: "high" },
  },
  { kind: "retry", index: 1, path: "src/a.ts", reply: "not json" },
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
});

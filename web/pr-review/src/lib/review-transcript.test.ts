import { describe, expect, it } from "vitest";
import type { ReviewEvent } from "./review-event";
import { applyEvent, initialReviewState, reduceEvents } from "./review-state";

const filePrompt = (index: number, attempt: number, user: string): ReviewEvent => ({
  kind: "prompt",
  scope: "file",
  index,
  path: `src/f${index}.ts`,
  attempt,
  system: "system text",
  user,
});

const fileReply = (index: number, attempt: number, text: string): ReviewEvent => ({
  kind: "reply_text",
  scope: "file",
  index,
  attempt,
  text,
});

const summaryPrompt: ReviewEvent = {
  kind: "prompt",
  scope: "summary",
  attempt: 1,
  system: "summary system",
  user: "summary user",
};

describe("review transcript state", () => {
  it("opens an attempt on prompt and appends reply text to it", () => {
    const state = reduceEvents([
      filePrompt(1, 1, "user text"),
      fileReply(1, 1, "Hel"),
      fileReply(1, 1, "lo"),
    ]);

    expect(state.transcript).toEqual([
      {
        scope: "file",
        index: 1,
        path: "src/f1.ts",
        attempts: [
          { attempt: 1, system: "system text", user: "user text", reply: "Hello", done: false },
        ],
      },
    ]);
  });

  it("keeps the first attempt done when a retry prompt opens the second", () => {
    const state = reduceEvents([
      filePrompt(1, 1, "first user"),
      fileReply(1, 1, "not json"),
      filePrompt(1, 2, "retry user"),
      fileReply(1, 2, "{}"),
    ]);
    const [entry] = state.transcript;

    expect(entry.attempts.map((attempt) => attempt.done)).toEqual([true, false]);
    expect(entry.attempts[1]).toMatchObject({ attempt: 2, user: "retry user", reply: "{}" });
  });

  it("marks the open attempt done on file_done, error and end", () => {
    const fileDone = reduceEvents([
      filePrompt(1, 1, "user"),
      { kind: "file_done", index: 1, path: "src/f1.ts", outcome: "clean", seconds: 1 },
    ]);
    const errored = reduceEvents([filePrompt(1, 1, "user"), { kind: "error", message: "boom" }]);
    const ended = reduceEvents([filePrompt(1, 1, "user"), { kind: "end", status: "ok" }]);

    expect(fileDone.transcript[0].attempts[0].done).toBe(true);
    expect(errored.transcript[0].attempts[0].done).toBe(true);
    expect(ended.transcript[0].attempts[0].done).toBe(true);
  });

  it("keeps a summary entry last and marks it done on summary", () => {
    const state = reduceEvents([
      summaryPrompt,
      filePrompt(2, 1, "second file"),
      filePrompt(1, 1, "first file"),
      { kind: "summary", text: "all good" },
    ]);

    expect(state.transcript.map((entry) => entry.scope === "summary" ? "summary" : entry.index)).toEqual([
      1,
      2,
      "summary",
    ]);
    const summary = state.transcript[2];
    expect(summary).toMatchObject({ scope: "summary", index: null, path: "" });
    expect(summary.attempts).toEqual([
      { attempt: 1, system: "summary system", user: "summary user", reply: "", done: true },
    ]);
  });

  it("ignores reply text that has no matching prompt", () => {
    const state = reduceEvents([fileReply(1, 1, "orphan")]);

    expect(state.transcript).toEqual([]);
  });

  it("applies a duplicate event id once", () => {
    const opened = applyEvent(initialReviewState, filePrompt(1, 1, "user"), 1);
    const once = applyEvent(opened, fileReply(1, 1, "a"), 2);
    const twice = applyEvent(once, fileReply(1, 1, "a"), 2);

    expect(twice.transcript[0].attempts[0].reply).toBe("a");
  });

  it("gives an empty transcript for a log with no transcript events", () => {
    const state = reduceEvents([
      { kind: "start", name: "PR #1", title: "Old", model: "qwen" },
      { kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 10 },
      { kind: "file_done", index: 1, total: 1, path: "src/a.ts", outcome: "clean", seconds: 1 },
      { kind: "end", status: "ok" },
    ]);

    expect(state.transcript).toEqual([]);
  });
});

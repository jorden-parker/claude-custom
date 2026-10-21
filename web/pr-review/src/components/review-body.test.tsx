import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { reduceEvents } from "@/lib/review-state";
import { ReviewBody } from "./review-body";

const hostile = "<img src=x onerror=alert(1)>";

const runningFileEvents = [
  { kind: "start", name: "PR #7", title: "Hostile", model: "qwen", base_url: "" },
  { kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 10 },
  {
    kind: "finding",
    index: 1,
    path: "src/a.ts",
    finding: { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary: hostile, why: hostile, confidence: "high" },
  },
  { kind: "retry", index: 1, path: "src/a.ts", reply: hostile },
];

describe("ReviewBody", () => {
  it("renders model text as text, never as HTML", () => {
    const state = reduceEvents([...runningFileEvents, { kind: "summary", text: hostile }]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(markup).not.toContain("<img");
  });

  it("shows the finished elapsed time and a done status once ended", () => {
    const state = reduceEvents([
      { kind: "start", t: 0, name: "PR #3", title: "t", model: "m", base_url: "" },
      { kind: "end", t: 79, status: "ok" },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={0} />);

    expect(markup).toContain("79s");
    expect(markup).toContain(">done<");
    expect(markup).not.toContain(">ok<");
  });

  it("shows the waiting seconds for the first token", () => {
    const state = reduceEvents([
      { kind: "file_start", t: 1, index: 1, total: 1, path: "src/a.ts", chars: 1 },
      { kind: "waiting", t: 13, seconds: 12 },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={13} />);

    expect(markup).toContain("waiting for the first token, 12s");
  });

  it("renders the file heading, finding location and verdict", () => {
    const state = reduceEvents([
      ...runningFileEvents,
      { kind: "verdict", verdict: "REQUEST CHANGES", seconds: 3 },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("[1/1] src/a.ts");
    expect(markup).toContain("src/a.ts:3");
    expect(markup).toContain("REQUEST CHANGES");
  });
});

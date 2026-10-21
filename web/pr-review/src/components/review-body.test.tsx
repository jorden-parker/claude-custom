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

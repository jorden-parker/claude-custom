import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { markStopped, reduceEvents } from "@/lib/review-state";
import { ReviewBody } from "./review-body";

const hostile = "<img src=x onerror=alert(1)>";

const runningFileEvents = [
  { kind: "start", name: "PR #7", title: "Hostile", model: "qwen", base_url: "" },
  { kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 10 },
  { kind: "retry", index: 1, path: "src/a.ts", reply: hostile },
  {
    kind: "finding",
    index: 1,
    path: "src/a.ts",
    finding: { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary: hostile, why: hostile, confidence: "high" },
  },
];

function eventsWithFinding(summary: string, why: string) {
  return [
    { kind: "start", name: "PR #7", title: "t", model: "qwen", base_url: "" },
    { kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 10 },
    {
      kind: "finding",
      index: 1,
      path: "src/a.ts",
      finding: { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary, why, confidence: "high" },
    },
  ];
}

describe("ReviewBody", () => {
  it("renders inline markdown in a finding summary", () => {
    const state = reduceEvents(eventsWithFinding("Use `shell=False` and **quote** it", ""));
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("<code>shell=False</code>");
    expect(markup).toContain("<strong>quote</strong>");
  });

  it("never renders raw HTML from finding text", () => {
    const state = reduceEvents(eventsWithFinding(hostile, hostile));
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).not.toContain("<img");
  });

  it("drops a javascript link target from finding text", () => {
    const state = reduceEvents(eventsWithFinding("[x](javascript:alert(1))", ""));
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).not.toContain("javascript:");
  });

  it("shows a retry reply as literal text", () => {
    const state = reduceEvents([
      { kind: "start", name: "PR #7", title: "t", model: "qwen", base_url: "" },
      { kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 10 },
      { kind: "retry", index: 1, path: "src/a.ts", reply: "**not bold**" },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("**not bold**");
    expect(markup).not.toContain("<strong>");
  });

  it("renders model text as text, never as HTML", () => {
    const state = reduceEvents([...runningFileEvents, { kind: "summary", text: hostile }]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(markup).not.toContain("<img");
  });

  it("never requests an http image from model text, keeping only its alt text", () => {
    const state = reduceEvents([
      ...runningFileEvents,
      { kind: "summary", text: "![Build badge](http://10.0.0.5/admin?action=x)" },
      { kind: "verdict", verdict: "REQUEST CHANGES", seconds: 3 },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("Build badge");
    expect(markup).not.toContain("<img");
    expect(markup).not.toContain('rel="preload"');
    expect(markup).not.toContain("10.0.0.5");
  });

  it("shows the alt text of a relative-path image without emitting an image", () => {
    const state = reduceEvents([
      ...runningFileEvents,
      { kind: "summary", text: "![Architecture diagram](docs/diagram.png)" },
      { kind: "verdict", verdict: "REQUEST CHANGES", seconds: 3 },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("Architecture diagram");
    expect(markup).not.toContain("<img");
    expect(markup).not.toContain("docs/diagram.png");
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

describe("ReviewBody review states", () => {
  const started = { kind: "start", t: 0, name: "PR #9", title: "states", model: "qwen", base_url: "" };
  const fileStarted = { kind: "file_start", t: 1, index: 1, total: 2, path: "src/a.ts", chars: 10 };

  it("colors labels and shows confidence only when it is not high", () => {
    const state = reduceEvents([
      started,
      fileStarted,
      { kind: "finding", index: 1, path: "src/a.ts", finding: { label: "question", blocking: false, path: "src/a.ts", line: 2, summary: "Why?", why: "", confidence: "low" } },
      { kind: "finding", index: 1, path: "src/a.ts", finding: { label: "praise", blocking: false, path: "src/a.ts", line: 4, summary: "Nice", why: "", confidence: "high" } },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("bg-blue-600");
    expect(markup).toContain("bg-green-600");
    expect(markup).toContain("confidence: low");
    expect(markup).not.toContain("confidence: high");
  });

  it("shows only the path when a finding has no line", () => {
    const state = reduceEvents([
      started,
      fileStarted,
      { kind: "finding", index: 1, path: "docs/a.md", finding: { label: "issue", blocking: false, path: "docs/a.md", line: null, summary: "Doc", why: "", confidence: "high" } },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain(">docs/a.md<");
    expect(markup).not.toContain("null");
  });

  it("shows the running file as stopped, not spinning, when an error ends the review", () => {
    const state = reduceEvents([
      started,
      fileStarted,
      { kind: "error", t: 2, message: "request failed" },
      { kind: "end", t: 2, status: "error" },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain(">failed<");
    expect(markup).toContain("request failed");
    expect(markup).toContain("stopped before a result");
    expect(markup).not.toContain("animate-spin");
  });

  it("marks a stopped review with a note, a grey pill and no spinners", () => {
    const state = markStopped(reduceEvents([started, fileStarted, { kind: "waiting", t: 3, seconds: 2 }]));
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={900} />);

    expect(markup).toContain(">stopped<");
    expect(markup).toContain("The review ended without a result.");
    expect(markup).not.toContain("animate-spin");
    expect(markup).not.toContain("animate-pulse");
  });

  it("shows what the check kept and the retried reply as preformatted text", () => {
    const state = reduceEvents([
      started,
      fileStarted,
      { kind: "retry", t: 2, index: 1, path: "src/a.ts", reply: "**raw**" },
      { kind: "check", t: 3, index: 1, path: "src/a.ts", count: 6, kept: 4 },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("retried: the answer was not a JSON array");
    expect(markup).toContain("<pre");
    expect(markup).toContain("checked 6 findings, kept 4");
  });

  it("shows a file still running when the review errored as a stopped chip, with the full path as title", () => {
    const longPath = `src/generated/${"x".repeat(120)}.ts`;
    const state = reduceEvents([
      started,
      { kind: "file_start", t: 1, index: 1, total: 1, path: longPath, chars: 10 },
      { kind: "error", t: 2, message: "failed" },
      { kind: "end", t: 2, status: "error" },
    ]);
    const markup = renderToStaticMarkup(<ReviewBody state={state} elapsedSeconds={5} />);

    expect(markup).toContain("stopped");
    expect(markup).not.toContain("running");
    expect(markup).toContain(`title="${longPath}"`);
    expect(markup).toContain("truncate");
    expect(markup).toContain("text-left");
  });
});

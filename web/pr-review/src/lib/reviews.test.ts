import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  listReviews,
  logDir,
  isReviewId,
  parseEvents,
  resolveReviewFile,
  summarize,
} from "./reviews";

const COMPLETE_ID = "20261021-174512-pr-7";
const RUNNING_ID = "20261021-180000-main..widget";

const completeLog = [
  { t: 0, kind: "start", name: "PR #7", title: "Fix parser", model: "qwen", base_url: "http://localhost:11434" },
  { t: 1, kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 120 },
  { t: 2, kind: "finding", index: 1, path: "src/a.ts", finding: { label: "issue", blocking: true, path: "src/a.ts", line: 3, summary: "Null deref <b>x</b>", why: "x can be null", confidence: "high" } },
  { t: 3, kind: "file_done", index: 1, total: 1, path: "src/a.ts", outcome: "ok", seconds: 2 },
  { t: 4, kind: "verdict", verdict: "REQUEST CHANGES", seconds: 4 },
  { t: 5, kind: "end", status: "ok" },
];

const runningLog = [
  { t: 0, kind: "start", name: "main..widget", title: "Widget", model: "qwen", base_url: "http://localhost:11434" },
  { t: 1, kind: "stage", message: "fetching diff" },
];

function toJsonl(events: object[]): string {
  return events.map((event) => JSON.stringify(event)).join("\n") + "\n";
}

describe("review log reading", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "reviews-"));
    process.env.PR_REVIEW_LOG_DIR = dir;
    fs.writeFileSync(path.join(dir, `${COMPLETE_ID}.jsonl`), toJsonl(completeLog));
    fs.writeFileSync(path.join(dir, `${RUNNING_ID}.jsonl`), toJsonl(runningLog));
    const old = new Date(Date.now() - 11 * 60_000);
    fs.utimesSync(path.join(dir, `${RUNNING_ID}.jsonl`), old, old);
  });

  afterEach(() => {
    delete process.env.PR_REVIEW_LOG_DIR;
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("uses PR_REVIEW_LOG_DIR when it is set", () => {
    expect(logDir()).toBe(dir);
  });

  it("summarizes a complete review", () => {
    const events = parseEvents(toJsonl(completeLog));
    const summary = summarize(COMPLETE_ID, events, Date.now(), Date.now());
    expect(summary).toEqual({
      id: COMPLETE_ID,
      name: "PR #7",
      title: "Fix parser",
      model: "qwen",
      status: "ok",
      verdict: "REQUEST CHANGES",
      seconds: 4,
      findings: 1,
      started: "2026-10-21T17:45:12.000Z",
    });
  });

  it("reports a running review without an end event", () => {
    const events = parseEvents(toJsonl(runningLog));
    const now = Date.now();
    const summary = summarize(RUNNING_ID, events, now, now);
    expect(summary.status).toBe("running");
    expect(summary.verdict).toBeNull();
    expect(summary.seconds).toBeNull();
  });

  it("reports stopped after ten minutes without an end event", () => {
    const events = parseEvents(toJsonl(runningLog));
    const now = Date.now();
    const summary = summarize(RUNNING_ID, events, now - 600_001, now);
    expect(summary.status).toBe("stopped");
  });

  it("skips bad lines and lines without a string kind", () => {
    const text = `not json\n{"kind": 5}\n{"t": 1}\n${JSON.stringify({ kind: "stage", message: "ok" })}\n`;
    expect(parseEvents(text)).toEqual([{ kind: "stage", message: "ok" }]);
  });

  it("lists reviews newest first and gives an empty list for a missing directory", () => {
    const names = listReviews().map((review) => review.id);
    expect(names).toEqual([RUNNING_ID, COMPLETE_ID]);

    process.env.PR_REVIEW_LOG_DIR = path.join(dir, "missing");
    expect(listReviews()).toEqual([]);
  });

  it("rejects traversal, unknown and suffixed ids", () => {
    expect(isReviewId("../../etc/passwd")).toBe(false);
    expect(isReviewId("nope")).toBe(false);
    expect(resolveReviewFile(`${COMPLETE_ID}.jsonl`)).toBeNull();
    expect(resolveReviewFile("../../etc/passwd")).toBeNull();
  });

  it("accepts range slugs such as main..widget", () => {
    expect(isReviewId(RUNNING_ID)).toBe(true);
    expect(resolveReviewFile(RUNNING_ID)).toBe(path.join(dir, `${RUNNING_ID}.jsonl`));
  });
});

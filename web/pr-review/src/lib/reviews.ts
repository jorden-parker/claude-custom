import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseReviewEvent, type ReviewEvent } from "./review-event";

export type ReviewStatus = "running" | "stopped" | "ok" | "error";

export type ReviewSummary = {
  id: string;
  name: string;
  title: string;
  model: string;
  status: ReviewStatus;
  verdict: string | null;
  seconds: number | null;
  findings: number;
  started: string;
};

const REVIEW_ID_PATTERN = /^[0-9]{8}-[0-9]{6}-[A-Za-z0-9._-]+$/;
const STOPPED_AFTER_MS = 600_000;

export function logDir(): string {
  return (
    process.env.PR_REVIEW_LOG_DIR ||
    path.join(os.homedir(), ".local/share/claude-custom/reviews")
  );
}

export function isReviewId(id: string): boolean {
  return REVIEW_ID_PATTERN.test(id);
}

export function resolveReviewFile(id: string): string | null {
  if (!isReviewId(id)) {
    return null;
  }
  const directory = logDir();
  const file = path.resolve(directory, `${id}.jsonl`);
  if (path.dirname(file) !== path.resolve(directory)) {
    return null;
  }
  return fs.existsSync(file) ? file : null;
}

export function parseEvents(text: string): ReviewEvent[] {
  const events: ReviewEvent[] = [];
  for (const line of text.split("\n")) {
    const event = parseReviewEvent(line);
    if (event) {
      events.push(event);
    }
  }
  return events;
}

export function isStoppedReview(file: string): boolean {
  const events = parseEvents(fs.readFileSync(file, "utf8"));
  const id = path.basename(file, ".jsonl");
  return summarize(id, events, fs.statSync(file).mtimeMs, Date.now()).status === "stopped";
}

export function summarize(
  id: string,
  events: ReviewEvent[],
  mtimeMs: number,
  now: number,
): ReviewSummary {
  const start = events.find((event) => event.kind === "start");
  const verdict = events.find((event) => event.kind === "verdict");
  const end = events.find((event) => event.kind === "end");
  return {
    id,
    name: textField(start, "name"),
    title: textField(start, "title"),
    model: textField(start, "model"),
    status: statusOf(end, mtimeMs, now),
    verdict: verdict ? textField(verdict, "verdict") : null,
    seconds: verdict ? numberField(verdict, "seconds") : null,
    findings: events.filter((event) => event.kind === "finding").length,
    started: startedFromId(id),
  };
}

function statusOf(
  end: ReviewEvent | undefined,
  mtimeMs: number,
  now: number,
): ReviewStatus {
  if (end) {
    return end.status === "error" ? "error" : "ok";
  }
  return now - mtimeMs > STOPPED_AFTER_MS ? "stopped" : "running";
}

function textField(event: ReviewEvent | undefined, field: string): string {
  const value = event?.[field];
  return typeof value === "string" ? value : "";
}

function numberField(event: ReviewEvent, field: string): number | null {
  const value = event[field];
  return typeof value === "number" ? value : null;
}

function startedFromId(id: string): string {
  const match = /^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})/.exec(id);
  if (!match) {
    return "";
  }
  const [, year, month, day, hour, minute, second] = match;
  return new Date(
    Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute), Number(second)),
  ).toISOString();
}

export function listReviews(): ReviewSummary[] {
  const directory = logDir();
  if (!fs.existsSync(directory)) {
    return [];
  }
  const now = Date.now();
  return fs
    .readdirSync(directory)
    .filter((name) => name.endsWith(".jsonl"))
    .sort()
    .reverse()
    .map((name) => {
      const id = name.slice(0, -".jsonl".length);
      const file = path.join(directory, name);
      const text = fs.readFileSync(file, "utf8");
      const mtimeMs = fs.statSync(file).mtimeMs;
      return summarize(id, parseEvents(text), mtimeMs, now);
    });
}

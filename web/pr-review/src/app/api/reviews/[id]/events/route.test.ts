import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GET } from "./route";

const REVIEW_ID = "20261021-174512-pr-7";
const READ_TIMEOUT_MS = 5000;

type Context = { params: Promise<{ id: string }> };

function contextFor(id: string): Context {
  return { params: Promise.resolve({ id }) };
}

function withTimeout<T>(promise: Promise<T>, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timed out waiting for ${label}`)), READ_TIMEOUT_MS);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function readUntil(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  decoder: TextDecoder,
  isDone: (text: string) => boolean,
): Promise<string> {
  let text = "";
  while (!isDone(text)) {
    const chunk = await withTimeout(reader.read(), "stream data");
    if (chunk.done) {
      break;
    }
    text += decoder.decode(chunk.value, { stream: true });
  }
  return text;
}

describe("GET /api/reviews/[id]/events", () => {
  let dir: string;
  let logFile: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "events-"));
    process.env.PR_REVIEW_LOG_DIR = dir;
    logFile = path.join(dir, `${REVIEW_ID}.jsonl`);
    fs.writeFileSync(
      logFile,
      `${JSON.stringify({ t: 0, kind: "start", name: "PR #7", title: "t", model: "m", base_url: "b" })}\n` +
        `${JSON.stringify({ t: 1, kind: "stage", message: "fetching" })}\n`,
    );
  });

  afterEach(() => {
    delete process.env.PR_REVIEW_LOG_DIR;
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("returns 404 for an invalid id", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/reviews/nope/events"), contextFor("nope"));
    expect(response.status).toBe(404);
  });

  it("returns 404 when the review file does not exist", async () => {
    const id = "20261021-180000-missing";
    const response = await GET(new Request("http://127.0.0.1/x"), contextFor(id));
    expect(response.status).toBe(404);
  });

  it("replays, tails appended lines, then closes after end", async () => {
    const controller = new AbortController();
    const response = await GET(
      new Request("http://127.0.0.1/x", { signal: controller.signal }),
      contextFor(REVIEW_ID),
    );
    expect(response.headers.get("Content-Type")).toBe("text/event-stream");
    expect(response.headers.get("Cache-Control")).toBe("no-cache, no-transform");

    const reader = response.body!.getReader();
    const decoder = new TextDecoder();

    const replayed = await readUntil(reader, decoder, (text) => text.includes('"stage"'));
    expect(replayed).toContain(`data: ${JSON.stringify({ t: 0, kind: "start", name: "PR #7", title: "t", model: "m", base_url: "b" })}\n\n`);
    expect(replayed).toContain('data: {"t":1,"kind":"stage","message":"fetching"}\n\n');

    fs.appendFileSync(logFile, '{"t":2,"kind":"finding"');
    fs.appendFileSync(logFile, ',"index":1}\n');
    const tailed = await readUntil(reader, decoder, (text) => text.includes('"finding"'));
    expect(tailed).toContain('data: {"t":2,"kind":"finding","index":1}\n\n');

    fs.appendFileSync(logFile, '{"t":3,"kind":"end","status":"ok"}\n');
    const rest = await readUntil(reader, decoder, () => false);
    expect(rest).toContain('"end"');
    const closed = await withTimeout(reader.read(), "stream close");
    expect(closed.done).toBe(true);
  });

  it("closes when the request is aborted", async () => {
    const controller = new AbortController();
    const response = await GET(
      new Request("http://127.0.0.1/x", { signal: controller.signal }),
      contextFor(REVIEW_ID),
    );
    const reader = response.body!.getReader();
    await readUntil(reader, new TextDecoder(), (text) => text.includes('"stage"'));

    controller.abort();
    const closed = await withTimeout(reader.read(), "abort close");
    expect(closed.done).toBe(true);
  });
});

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GET } from "./route";

const RUN_ID = "20261026-101500-doctor-3fa9";
const READ_TIMEOUT_MS = 5000;

function contextFor(id: string) {
  return { params: Promise.resolve({ id }) };
}

function withTimeout<T>(promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timed out waiting for stream data")), READ_TIMEOUT_MS);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function readUntil(reader: ReadableStreamDefaultReader<Uint8Array>, isDone: (text: string) => boolean) {
  const decoder = new TextDecoder();
  let text = "";
  while (!isDone(text)) {
    const chunk = await withTimeout(reader.read());
    if (chunk.done) {
      break;
    }
    text += decoder.decode(chunk.value, { stream: true });
  }
  return text;
}

describe("GET /api/runs/[id]/events", () => {
  let stateDir: string;
  let logFile: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "run-events-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
    fs.mkdirSync(path.join(stateDir, "runs"));
    logFile = path.join(stateDir, "runs", `${RUN_ID}.jsonl`);
    fs.writeFileSync(logFile, `${JSON.stringify({ t: 0, kind: "start", id: RUN_ID, pid: 1 })}\n`);
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("answers 404 for an id that is not a run", async () => {
    const response = await GET(new Request("http://127.0.0.1/x"), contextFor("../../etc"));
    expect(response.status).toBe(404);
  });

  it("replays the log, tails appended lines and closes after the end event", async () => {
    const controller = new AbortController();
    const response = await GET(new Request("http://127.0.0.1/x", { signal: controller.signal }), contextFor(RUN_ID));
    expect(response.headers.get("Content-Type")).toBe("text/event-stream");
    const reader = response.body!.getReader();

    const replayed = await readUntil(reader, (text) => text.includes('"kind":"start"'));
    expect(replayed).toContain("id: 1\ndata: ");

    fs.appendFileSync(logFile, `${JSON.stringify({ t: 1, kind: "line", stream: "stdout", text: "ok" })}\n`);
    fs.appendFileSync(logFile, `${JSON.stringify({ t: 2, kind: "end", code: 0, cancelled: false })}\n`);
    const tail = await readUntil(reader, () => false);

    expect(tail).toContain('"kind":"end"');
    expect((await withTimeout(reader.read())).done).toBe(true);
    controller.abort();
  });
});

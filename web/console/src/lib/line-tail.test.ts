import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { streamLines } from "./line-tail";

const READ_TIMEOUT_MS = 5000;
const isNotEnd = () => false;
const isEnd = (line: string) => line === "END";
const frameOf = (lineNumber: number, line: string) => `id: ${lineNumber}\ndata: ${line}\n\n`;

function withTimeout<T>(promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timed out")), READ_TIMEOUT_MS);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function readUntil(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  isDone: (text: string) => boolean,
): Promise<string> {
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

describe("streamLines", () => {
  let directory: string;
  let file: string;
  let controller: AbortController;

  beforeEach(async () => {
    directory = await fs.mkdtemp(path.join(os.tmpdir(), "line-tail-"));
    file = path.join(directory, "run.jsonl");
    await fs.writeFile(file, "");
    controller = new AbortController();
  });

  afterEach(async () => {
    controller.abort();
    await fs.rm(directory, { recursive: true, force: true });
  });

  it("frames each appended line", async () => {
    const reader = streamLines(file, controller.signal, { skipLines: 0, isEnd: isNotEnd, frame: frameOf }).getReader();
    await fs.appendFile(file, "first\nsecond\n");
    const text = await readUntil(reader, (received) => received.includes("data: second"));
    expect(text).toBe("id: 1\ndata: first\n\nid: 2\ndata: second\n\n");
  });

  it("closes after the line that isEnd accepts", async () => {
    const reader = streamLines(file, controller.signal, { skipLines: 0, isEnd, frame: frameOf }).getReader();
    await fs.appendFile(file, "work\nEND\n");
    const text = await readUntil(reader, () => false);
    expect(text).toBe("id: 1\ndata: work\n\nid: 2\ndata: END\n\n");
    expect((await withTimeout(reader.read())).done).toBe(true);
  });

  it("skips the first skipLines lines", async () => {
    const reader = streamLines(file, controller.signal, { skipLines: 1, isEnd: isNotEnd, frame: frameOf }).getReader();
    await fs.appendFile(file, "one\ntwo\n");
    const text = await readUntil(reader, (received) => received.includes("data: two"));
    expect(text).toBe("id: 2\ndata: two\n\n");
  });

  it("sends nothing for a line whose frame is null but still reads on", async () => {
    const frameSkippingOne = (lineNumber: number, line: string) =>
      line === "hidden" ? null : frameOf(lineNumber, line);
    const reader = streamLines(file, controller.signal, {
      skipLines: 0,
      isEnd: isNotEnd,
      frame: frameSkippingOne,
    }).getReader();
    await fs.appendFile(file, "hidden\nshown\n");
    const text = await readUntil(reader, (received) => received.includes("data: shown"));
    expect(text).toBe("id: 2\ndata: shown\n\n");
  });

  it("ignores blank lines", async () => {
    const reader = streamLines(file, controller.signal, { skipLines: 0, isEnd: isNotEnd, frame: frameOf }).getReader();
    await fs.appendFile(file, "\n   \nlast\n");
    const text = await readUntil(reader, (received) => received.includes("data: last"));
    expect(text).toBe("id: 3\ndata: last\n\n");
  });
});

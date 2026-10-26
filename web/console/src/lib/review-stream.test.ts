import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { streamReviewEvents } from "./review-stream";

const POLL_WAIT_MS = 600;

describe("streamReviewEvents", () => {
  let directory: string;
  let file: string;
  let controller: AbortController;
  let reader: ReadableStreamDefaultReader<Uint8Array>;
  const decoder = new TextDecoder();

  beforeEach(async () => {
    directory = await fs.mkdtemp(path.join(os.tmpdir(), "review-stream-"));
    file = path.join(directory, "review.jsonl");
    controller = new AbortController();
  });

  afterEach(async () => {
    controller.abort();
    vi.restoreAllMocks();
    await fs.rm(directory, { recursive: true, force: true });
  });

  function open(skipLines = 0) {
    reader = streamReviewEvents(file, controller.signal, skipLines).getReader();
  }

  async function readUntil(done: (text: string) => boolean): Promise<string> {
    let text = "";
    while (!done(text)) {
      const chunk = await reader.read();
      if (chunk.done) {
        break;
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    return text;
  }

  it("delivers lines appended after the stream starts", async () => {
    await fs.writeFile(file, "first\n");
    open();

    const initial = await readUntil((text) => text.includes("data: first"));
    await fs.appendFile(file, "second\n");
    const appended = await readUntil((text) => text.includes("data: second"));

    expect(initial).toContain("id: 1\ndata: first\n\n");
    expect(appended).toContain("id: 2\ndata: second\n\n");
  });

  it("resumes after the skipped lines on reconnect", async () => {
    await fs.writeFile(file, "one\ntwo\nthree\nfour\n");
    open(2);

    const text = await readUntil((value) => value.includes("data: four"));

    expect(text).toBe("id: 3\ndata: three\n\nid: 4\ndata: four\n\n");
  });

  it("keeps a multi-byte character split across two appends intact", async () => {
    const euro = Buffer.from("€ rate\n", "utf8");
    await fs.writeFile(file, euro.subarray(0, 1));
    open();

    await fs.appendFile(file, euro.subarray(1));
    const text = await readUntil((value) => value.includes("rate"));

    expect(text).toContain("id: 1\ndata: € rate\n\n");
  });

  it("holds a partial line until its newline arrives", async () => {
    await fs.writeFile(file, "half");
    open();
    const waiting = readUntil((value) => value.includes("data:"));

    await fs.appendFile(file, " line\n");

    expect(await waiting).toContain("id: 1\ndata: half line\n\n");
  });

  it("reads each byte of a 2 MB log once while polling an unchanged file", async () => {
    const line = `${"x".repeat(1023)}\n`;
    const body = line.repeat(2048);
    await fs.writeFile(file, body);
    const realOpen = fs.open;
    const bytesRead: number[] = [];
    vi.spyOn(fs, "open").mockImplementation(async (...args) => {
      const handle = await realOpen(...args);
      const realRead = handle.read.bind(handle);
      vi.spyOn(handle, "read").mockImplementation(async (...args: Parameters<typeof realRead>) => {
        const result = await realRead(...args);
        bytesRead.push(result.bytesRead);
        return result;
      });
      return handle;
    });

    open();
    await readUntil((value) => value.includes("id: 2048\n"));
    await new Promise((resolve) => setTimeout(resolve, POLL_WAIT_MS));

    expect(bytesRead.reduce((total, count) => total + count, 0)).toBe(Buffer.byteLength(body));
  });
});

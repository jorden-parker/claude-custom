import fs, { type FileHandle } from "node:fs/promises";
import { parseReviewEvent } from "./review-event";

const POLL_INTERVAL_MS = 250;
const KEEP_ALIVE_INTERVAL_MS = 15_000;
const KEEP_ALIVE_FRAME = ": keep-alive\n\n";
const NEWLINE_BYTE = 0x0a;
const NO_BYTES = Buffer.alloc(0);
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function parseLastEventId(value: string | null): number {
  return /^[1-9]\d*$/.test(value ?? "") ? Number(value) : 0;
}

export function streamReviewEvents(
  file: string,
  signal: AbortSignal,
  skipLines = 0,
): ReadableStream<Uint8Array> {
  let linesSeen = 0;
  let byteOffset = 0;
  let partialLine = NO_BYTES;
  let closed = false;
  let pollTimer: ReturnType<typeof setTimeout> | undefined;
  let keepAliveTimer: ReturnType<typeof setInterval> | undefined;
  let stop = () => {};

  return new ReadableStream<Uint8Array>({
    start(controller) {
      const send = (frame: string) => {
        if (!closed) {
          controller.enqueue(encoder.encode(frame));
        }
      };

      const close = () => {
        if (closed) {
          return;
        }
        closed = true;
        clearTimeout(pollTimer);
        clearInterval(keepAliveTimer);
        signal.removeEventListener("abort", close);
        controller.close();
      };

      const sendLine = (lineNumber: number, line: string): boolean => {
        if (line.trim() === "") {
          return false;
        }
        send(`id: ${lineNumber}\ndata: ${line}\n\n`);
        return isEndLine(line);
      };

      const pumpNewLines = async () => {
        const appended = await readAppendedBytes(file, byteOffset);
        byteOffset += appended.length;
        partialLine = Buffer.concat([partialLine, appended]);
        let newlineAt = partialLine.indexOf(NEWLINE_BYTE);
        while (newlineAt !== -1) {
          const line = decoder.decode(partialLine.subarray(0, newlineAt));
          partialLine = partialLine.subarray(newlineAt + 1);
          linesSeen += 1;
          if (linesSeen > skipLines && sendLine(linesSeen, line)) {
            close();
            return;
          }
          newlineAt = partialLine.indexOf(NEWLINE_BYTE);
        }
      };

      const poll = async () => {
        await pumpNewLines();
        if (!closed) {
          pollTimer = setTimeout(poll, POLL_INTERVAL_MS);
        }
      };

      stop = close;
      signal.addEventListener("abort", close, { once: true });
      keepAliveTimer = setInterval(() => send(KEEP_ALIVE_FRAME), KEEP_ALIVE_INTERVAL_MS);
      void poll();
    },
    cancel() {
      stop();
    },
  });
}

async function readAppendedBytes(file: string, offset: number): Promise<Buffer> {
  let handle: FileHandle;
  try {
    handle = await fs.open(file, "r");
  } catch {
    return NO_BYTES;
  }
  try {
    const { size } = await handle.stat();
    if (size <= offset) {
      return NO_BYTES;
    }
    const buffer = Buffer.alloc(size - offset);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, offset);
    return buffer.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
}

function isEndLine(line: string): boolean {
  return parseReviewEvent(line)?.kind === "end";
}

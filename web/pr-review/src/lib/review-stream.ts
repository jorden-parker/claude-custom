import fs from "node:fs/promises";
import { parseReviewEvent } from "./review-event";

const POLL_INTERVAL_MS = 250;
const KEEP_ALIVE_INTERVAL_MS = 15_000;
const KEEP_ALIVE_FRAME = ": keep-alive\n\n";
const encoder = new TextEncoder();

export function parseLastEventId(value: string | null): number {
  return /^[1-9]\d*$/.test(value ?? "") ? Number(value) : 0;
}

export function streamReviewEvents(
  file: string,
  signal: AbortSignal,
  skipLines = 0,
): ReadableStream<Uint8Array> {
  let sentLines = skipLines;
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

      const pumpNewLines = async () => {
        const text = await fs.readFile(file, "utf8").catch(() => "");
        const completeLines = text.split("\n").slice(0, -1);
        let lineNumber = sentLines;
        for (const line of completeLines.slice(sentLines)) {
          lineNumber += 1;
          if (line.trim() === "") {
            continue;
          }
          send(`id: ${lineNumber}\ndata: ${line}\n\n`);
          if (isEndLine(line)) {
            close();
            return;
          }
        }
        sentLines = Math.max(sentLines, completeLines.length);
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

function isEndLine(line: string): boolean {
  return parseReviewEvent(line)?.kind === "end";
}

import fs from "node:fs/promises";
import { parseReviewEvent } from "./review-event";

const POLL_INTERVAL_MS = 250;
const KEEP_ALIVE_INTERVAL_MS = 15_000;
const KEEP_ALIVE_FRAME = ": keep-alive\n\n";
const encoder = new TextEncoder();

export function streamReviewEvents(
  file: string,
  signal: AbortSignal,
): ReadableStream<Uint8Array> {
  let sentCharacters = 0;
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
        const complete = text.slice(0, text.lastIndexOf("\n") + 1);
        const fresh = complete.slice(sentCharacters);
        sentCharacters = complete.length;
        for (const line of fresh.split("\n")) {
          if (line.trim() === "") {
            continue;
          }
          send(`data: ${line}\n\n`);
          if (isEndLine(line)) {
            close();
            return;
          }
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

function isEndLine(line: string): boolean {
  return parseReviewEvent(line)?.kind === "end";
}

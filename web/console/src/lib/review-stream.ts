import { parseReviewEvent } from "./review-event";
import { serverSentFrame, streamLines } from "./line-tail";

export function parseLastEventId(value: string | null): number {
  return /^[1-9]\d*$/.test(value ?? "") ? Number(value) : 0;
}

export function streamReviewEvents(
  file: string,
  signal: AbortSignal,
  skipLines = 0,
): ReadableStream<Uint8Array> {
  return streamLines(file, signal, {
    skipLines,
    isEnd: isEndLine,
    frame: serverSentFrame,
  });
}

function isEndLine(line: string): boolean {
  return parseReviewEvent(line)?.kind === "end";
}

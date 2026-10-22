import type { ReviewEvent } from "./review-event";

export type TranscriptAttempt = {
  attempt: number;
  system: string;
  user: string;
  reply: string;
  done: boolean;
};

export type TranscriptScope = "file" | "summary";

export type TranscriptEntry = {
  scope: TranscriptScope;
  index: number | null;
  path: string;
  attempts: TranscriptAttempt[];
};

type EntryTarget = { scope: TranscriptScope; index: number | null };
type Handler = (transcript: TranscriptEntry[], event: ReviewEvent) => TranscriptEntry[];

const handlers = new Map<string, Handler>([
  ["prompt", openAttempt],
  ["reply_text", appendReply],
  ["file_done", finishFile],
  ["summary", finishSummary],
  ["error", finishAll],
  ["end", finishAll],
]);

export function applyTranscriptEvent(
  transcript: TranscriptEntry[],
  event: ReviewEvent,
): TranscriptEntry[] {
  const handler = handlers.get(event.kind);
  return handler ? handler(transcript, event) : transcript;
}

function finishFile(transcript: TranscriptEntry[], event: ReviewEvent): TranscriptEntry[] {
  const index = numberField(event, "index");
  return finishEntries(transcript, (entry) => entry.scope === "file" && entry.index === index);
}

function finishSummary(transcript: TranscriptEntry[]): TranscriptEntry[] {
  return finishEntries(transcript, (entry) => entry.scope === "summary");
}

function finishAll(transcript: TranscriptEntry[]): TranscriptEntry[] {
  return finishEntries(transcript, () => true);
}

function openAttempt(transcript: TranscriptEntry[], event: ReviewEvent): TranscriptEntry[] {
  const target = targetOf(event);
  if (!target) {
    return transcript;
  }
  const opened: TranscriptAttempt = {
    attempt: numberField(event, "attempt") ?? 1,
    system: textField(event, "system"),
    user: textField(event, "user"),
    reply: "",
    done: false,
  };
  const existing = transcript.find((entry) => isSameEntry(entry, target));
  if (!existing) {
    const created: TranscriptEntry = {
      ...target,
      path: textField(event, "path"),
      attempts: [opened],
    };
    return sortEntries([...transcript, created]);
  }
  const updated: TranscriptEntry = {
    ...existing,
    attempts: [...existing.attempts.map(markDone), opened],
  };
  return transcript.map((entry) => (entry === existing ? updated : entry));
}

function appendReply(transcript: TranscriptEntry[], event: ReviewEvent): TranscriptEntry[] {
  const target = targetOf(event);
  const attemptNumber = numberField(event, "attempt");
  if (!target) {
    return transcript;
  }
  const text = textField(event, "text");
  return transcript.map((entry) =>
    isSameEntry(entry, target)
      ? {
          ...entry,
          attempts: entry.attempts.map((attempt) =>
            attempt.attempt === attemptNumber ? { ...attempt, reply: attempt.reply + text } : attempt,
          ),
        }
      : entry,
  );
}

function finishEntries(
  transcript: TranscriptEntry[],
  matches: (entry: TranscriptEntry) => boolean,
): TranscriptEntry[] {
  return transcript.map((entry) =>
    matches(entry) ? { ...entry, attempts: entry.attempts.map(markDone) } : entry,
  );
}

function markDone(attempt: TranscriptAttempt): TranscriptAttempt {
  return attempt.done ? attempt : { ...attempt, done: true };
}

function targetOf(event: ReviewEvent): EntryTarget | null {
  if (event.scope === "summary") {
    return { scope: "summary", index: null };
  }
  const index = numberField(event, "index");
  if (event.scope === "file" && index !== null) {
    return { scope: "file", index };
  }
  return null;
}

function isSameEntry(entry: TranscriptEntry, target: EntryTarget): boolean {
  return entry.scope === target.scope && entry.index === target.index;
}

function sortEntries(entries: TranscriptEntry[]): TranscriptEntry[] {
  return [...entries].sort((first, second) => orderOf(first) - orderOf(second));
}

function orderOf(entry: TranscriptEntry): number {
  return entry.scope === "summary" ? Number.MAX_SAFE_INTEGER : (entry.index ?? 0);
}

function textField(event: ReviewEvent, field: string): string {
  const value = event[field];
  return typeof value === "string" ? value : "";
}

function numberField(event: ReviewEvent, field: string): number | null {
  const value = event[field];
  return typeof value === "number" ? value : null;
}

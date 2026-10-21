import type { ReviewEvent } from "./review-event";

export type FileState = "waiting" | "writing" | "done";

export type FindingView = {
  label: string;
  blocking: boolean;
  path: string;
  line: number | null;
  summary: string;
  why: string;
  confidence: string;
};

export type CheckView = { count: number; kept: number | null };

export type FileView = {
  index: number;
  total: number;
  path: string;
  state: FileState;
  chars: number;
  waitingSeconds: number | null;
  findings: FindingView[];
  retries: string[];
  check: CheckView | null;
  outcome: string | null;
  seconds: number | null;
};

export type StageView = { t: number; message: string };

export type VerdictView = { verdict: string; seconds: number | null };

export type ReviewHeader = {
  name: string;
  title: string;
  model: string;
  status: "running" | "ok" | "error" | "stopped";
};

export type ReviewState = {
  header: ReviewHeader;
  stages: StageView[];
  files: FileView[];
  summary: string | null;
  verdict: VerdictView | null;
  report: string | null;
  error: string | null;
  ended: boolean;
  lastSeconds: number;
  lastEventId: number;
};

export const initialReviewState: ReviewState = {
  header: { name: "", title: "", model: "", status: "running" },
  stages: [],
  files: [],
  summary: null,
  verdict: null,
  report: null,
  error: null,
  ended: false,
  lastSeconds: 0,
  lastEventId: 0,
};

export function isFileOpenByDefault(file: FileView): boolean {
  return file.state !== "done" || file.findings.length > 0;
}

export function markStopped(state: ReviewState): ReviewState {
  if (state.ended) {
    return state;
  }
  return { ...state, ended: true, header: { ...state.header, status: "stopped" } };
}

export function reduceEvents(events: ReviewEvent[]): ReviewState {
  return events.reduce((state, event) => applyEvent(state, event), initialReviewState);
}

type Handler = (state: ReviewState, event: ReviewEvent) => ReviewState;

const handlers = new Map<string, Handler>([
  ["start", applyStart],
  ["stage", applyStage],
  ["file_start", applyFileStart],
  ["waiting", applyWaiting],
  ["writing", applyWriting],
  ["finding", applyFinding],
  ["retry", applyRetry],
  ["check", applyCheck],
  ["file_done", applyFileDone],
  ["summary", applySummary],
  ["verdict", applyVerdict],
  ["report", applyReport],
  ["error", applyError],
  ["end", applyEnd],
]);

export function applyEvent(state: ReviewState, event: ReviewEvent, eventId?: number): ReviewState {
  if (eventId !== undefined && eventId <= state.lastEventId) {
    return state;
  }
  const handler = handlers.get(event.kind);
  const next = handler ? handler(state, event) : state;
  return {
    ...next,
    lastEventId: eventId ?? next.lastEventId,
    lastSeconds: Math.max(next.lastSeconds, numberOf(event, "t") ?? 0),
  };
}

function applyStart(state: ReviewState, event: ReviewEvent): ReviewState {
  return {
    ...state,
    header: {
      ...state.header,
      name: textOf(event, "name"),
      title: textOf(event, "title"),
      model: textOf(event, "model"),
    },
  };
}

function applyStage(state: ReviewState, event: ReviewEvent): ReviewState {
  const stage = { t: numberOf(event, "t") ?? 0, message: textOf(event, "message") };
  return { ...state, stages: [...state.stages, stage] };
}

function applyFileStart(state: ReviewState, event: ReviewEvent): ReviewState {
  return upsertFile(state, indexOf(event), (file) => ({
    ...file,
    total: numberOf(event, "total") ?? file.total,
    path: textOf(event, "path"),
    state: "waiting",
    chars: numberOf(event, "chars") ?? 0,
  }));
}

function applyWaiting(state: ReviewState, event: ReviewEvent): ReviewState {
  return updateCurrentFile(state, (file) => ({
    ...file,
    state: "waiting",
    waitingSeconds: numberOf(event, "seconds"),
  }));
}

function applyWriting(state: ReviewState, event: ReviewEvent): ReviewState {
  return upsertFile(state, indexOf(event), (file) => ({
    ...file,
    state: "writing",
    chars: numberOf(event, "chars") ?? file.chars,
  }));
}

function applyFinding(state: ReviewState, event: ReviewEvent): ReviewState {
  return upsertFile(state, indexOf(event), (file) => ({
    ...file,
    findings: [...file.findings, findingOf(event)],
  }));
}

function applyRetry(state: ReviewState, event: ReviewEvent): ReviewState {
  return upsertFile(state, indexOf(event), (file) => ({
    ...file,
    retries: [...file.retries, textOf(event, "reply")],
  }));
}

function applyCheck(state: ReviewState, event: ReviewEvent): ReviewState {
  return upsertFile(state, indexOf(event), (file) => ({
    ...file,
    check: { count: numberOf(event, "count") ?? 0, kept: numberOf(event, "kept") },
  }));
}

function applyFileDone(state: ReviewState, event: ReviewEvent): ReviewState {
  return upsertFile(state, indexOf(event), (file) => ({
    ...file,
    state: "done",
    outcome: textOf(event, "outcome"),
    seconds: numberOf(event, "seconds"),
  }));
}

function applySummary(state: ReviewState, event: ReviewEvent): ReviewState {
  return { ...state, summary: textOf(event, "text") };
}

function applyVerdict(state: ReviewState, event: ReviewEvent): ReviewState {
  return {
    ...state,
    verdict: { verdict: textOf(event, "verdict"), seconds: numberOf(event, "seconds") },
  };
}

function applyReport(state: ReviewState, event: ReviewEvent): ReviewState {
  return { ...state, report: textOf(event, "markdown") };
}

function applyError(state: ReviewState, event: ReviewEvent): ReviewState {
  return { ...state, error: textOf(event, "message") };
}

function applyEnd(state: ReviewState, event: ReviewEvent): ReviewState {
  return {
    ...state,
    ended: true,
    header: { ...state.header, status: event.status === "error" ? "error" : "ok" },
  };
}

function indexOf(event: ReviewEvent): number {
  return numberOf(event, "index") ?? 0;
}

function upsertFile(
  state: ReviewState,
  index: number,
  change: (file: FileView) => FileView,
): ReviewState {
  const existing = state.files.find((file) => file.index === index);
  const base = existing ?? emptyFile(index);
  const updated = change(base);
  if (existing) {
    return { ...state, files: state.files.map((file) => (file.index === index ? updated : file)) };
  }
  return { ...state, files: [...state.files, updated] };
}

function updateCurrentFile(
  state: ReviewState,
  change: (file: FileView) => FileView,
): ReviewState {
  const current = state.files[state.files.length - 1];
  if (!current) {
    return state;
  }
  return upsertFile(state, current.index, change);
}

function emptyFile(index: number): FileView {
  return {
    index,
    total: 0,
    path: "",
    state: "waiting",
    chars: 0,
    waitingSeconds: null,
    findings: [],
    retries: [],
    check: null,
    outcome: null,
    seconds: null,
  };
}

function findingOf(event: ReviewEvent): FindingView {
  const finding = event.finding;
  const fields = typeof finding === "object" && finding !== null ? (finding as Record<string, unknown>) : {};
  return {
    label: typeof fields.label === "string" ? fields.label : "issue",
    blocking: fields.blocking === true,
    path: typeof fields.path === "string" ? fields.path : "",
    line: typeof fields.line === "number" ? fields.line : null,
    summary: typeof fields.summary === "string" ? fields.summary : "",
    why: typeof fields.why === "string" ? fields.why : "",
    confidence: typeof fields.confidence === "string" ? fields.confidence : "",
  };
}

function textOf(event: ReviewEvent, field: string): string {
  const value = event[field];
  return typeof value === "string" ? value : "";
}

function numberOf(event: ReviewEvent, field: string): number | null {
  const value = event[field];
  return typeof value === "number" ? value : null;
}

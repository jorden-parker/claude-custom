import type { RunEvent } from "./run-event";

export const MAX_LINES = 5000;

const STAGE_PATTERN = /^\[(\d+)\/(\d+)\] (.+)$/;
const REVIEW_LOG_PATTERN = /^log (.+\/)?([0-9]{8}-[0-9]{6}-[A-Za-z0-9._-]+)\.jsonl$/;

export type RunStream = "stdout" | "stderr";

export type RunLine = { stream: RunStream; text: string; t: number };

export type RunStage = { number: number; total: number; title: string };

export type RunState = {
  header: { command: string; label: string; startedAt: string } | null;
  lines: RunLine[];
  progress: Partial<Record<RunStream, string>>;
  stage: RunStage | null;
  ended: { code: number; cancelled: boolean } | null;
  seconds: number;
  lastEventId: number;
  reviewId: string | null;
};

export const initialRunState: RunState = {
  header: null,
  lines: [],
  progress: {},
  stage: null,
  ended: null,
  seconds: 0,
  lastEventId: 0,
  reviewId: null,
};

export function applyRunEvent(state: RunState, event: RunEvent, eventId?: number): RunState {
  if (eventId !== undefined && eventId <= state.lastEventId) {
    return state;
  }
  const next = applyKind(state, event);
  return {
    ...next,
    seconds: Math.max(next.seconds, numberOf(event.t) ?? 0),
    lastEventId: eventId ?? next.lastEventId,
  };
}

function applyKind(state: RunState, event: RunEvent): RunState {
  switch (event.kind) {
    case "start":
      return {
        ...state,
        header: {
          command: textOf(event.command),
          label: textOf(event.label),
          startedAt: textOf(event.started_at),
        },
      };
    case "line":
      return appendLine(state, event);
    case "progress":
      return { ...state, progress: { ...state.progress, [streamOf(event)]: textOf(event.text) } };
    case "end":
      return {
        ...state,
        progress: {},
        ended: { code: numberOf(event.code) ?? -1, cancelled: event.cancelled === true },
      };
    default:
      return state;
  }
}

function appendLine(state: RunState, event: RunEvent): RunState {
  const text = textOf(event.text);
  const line: RunLine = { stream: streamOf(event), text, t: numberOf(event.t) ?? 0 };
  const lines = [...state.lines, line];
  return {
    ...state,
    lines: lines.length > MAX_LINES ? lines.slice(lines.length - MAX_LINES) : lines,
    stage: stageOf(text) ?? state.stage,
    reviewId: reviewIdOf(text) ?? state.reviewId,
  };
}

function stageOf(text: string): RunStage | null {
  const match = STAGE_PATTERN.exec(text);
  if (!match) {
    return null;
  }
  return { number: Number(match[1]), total: Number(match[2]), title: match[3] };
}

function reviewIdOf(text: string): string | null {
  const match = REVIEW_LOG_PATTERN.exec(text);
  return match ? match[2] : null;
}

function streamOf(event: RunEvent): RunStream {
  return event.stream === "stderr" ? "stderr" : "stdout";
}

function textOf(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberOf(value: unknown): number | null {
  return typeof value === "number" ? value : null;
}

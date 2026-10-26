import { parseRunEvent } from "./run-event";
import type { RunStatus } from "./run-log";
import { applyRunEvent, type RunState } from "./run-state";

export type RunMessage = { data: string; lastEventId: string };

export function reduceRunMessage(state: RunState, message: RunMessage): RunState {
  const event = parseRunEvent(message.data);
  return event ? applyRunEvent(state, event, Number(message.lastEventId) || undefined) : state;
}

export function statusOf(state: RunState, serverStatus: RunStatus | null): RunStatus {
  if (state.ended) {
    if (state.ended.cancelled) {
      return "cancelled";
    }
    return state.ended.code === 0 ? "ok" : "failed";
  }
  return serverStatus ?? "running";
}

export function elapsedSeconds(state: RunState, now: number): number {
  if (state.ended || state.header === null || now === 0) {
    return state.seconds;
  }
  const started = Date.parse(state.header.startedAt);
  return Number.isNaN(started) ? state.seconds : Math.max(state.seconds, (now - started) / 1000);
}

export function formatElapsed(seconds: number): string {
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

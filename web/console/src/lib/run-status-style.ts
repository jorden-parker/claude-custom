import type { RunStatus } from "./run-log";

const labels: Record<RunStatus, string> = {
  running: "running",
  ok: "done",
  failed: "failed",
  cancelled: "cancelled",
  lost: "lost",
};

const textClasses: Record<RunStatus, string> = {
  running: "border-blue-600 text-blue-700 dark:text-blue-400",
  ok: "border-green-600 text-green-700 dark:text-green-400",
  failed: "border-red-600 text-red-700 dark:text-red-400",
  cancelled: "text-muted-foreground",
  lost: "border-amber-600 text-amber-700 dark:text-amber-400",
};

const dotClasses: Record<RunStatus, string> = {
  running: "animate-pulse bg-blue-500",
  ok: "bg-green-500",
  failed: "bg-red-500",
  cancelled: "bg-muted-foreground",
  lost: "bg-amber-500",
};

export function runStatusLabel(status: RunStatus): string {
  return labels[status];
}

export function runStatusTextClass(status: RunStatus): string {
  return textClasses[status];
}

export function runStatusDotClass(status: RunStatus): string {
  return `size-2 shrink-0 rounded-full ${dotClasses[status]}`;
}

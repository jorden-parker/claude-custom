import type { RunStatus } from "./run-log";

const labels: Record<RunStatus, string> = {
  running: "running",
  ok: "done",
  failed: "failed",
  cancelled: "cancelled",
  lost: "lost",
};

const textClasses: Record<RunStatus, string> = {
  running: "border-info-border text-info-foreground",
  ok: "border-success-border text-success-foreground",
  failed: "border-error-border text-error-foreground",
  cancelled: "text-muted-foreground",
  lost: "border-warning-border text-warning-foreground",
};

const dotClasses: Record<RunStatus, string> = {
  running: "animate-pulse bg-info-foreground",
  ok: "bg-success-foreground",
  failed: "bg-error-foreground",
  cancelled: "bg-muted-foreground",
  lost: "bg-warning-foreground",
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

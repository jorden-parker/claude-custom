import type { ReviewStatus } from "./reviews";

const headerLabels: Record<ReviewStatus, string> = {
  ok: "done",
  error: "failed",
  running: "running",
  stopped: "stopped",
};

const textClasses: Record<ReviewStatus, string> = {
  ok: "border-success-border text-success-foreground",
  error: "border-error-border text-error-foreground",
  running: "border-info-border text-info-foreground",
  stopped: "text-muted-foreground",
};

const dotClasses: Record<ReviewStatus, string> = {
  ok: "bg-success-foreground",
  error: "bg-error-foreground",
  running: "animate-pulse bg-info-foreground",
  stopped: "bg-muted-foreground",
};

export function headerStatusLabel(status: ReviewStatus): string {
  return headerLabels[status];
}

export function statusTextClass(status: ReviewStatus): string {
  return textClasses[status];
}

export function statusDotClass(status: ReviewStatus): string {
  return `size-2 shrink-0 rounded-full ${dotClasses[status]}`;
}

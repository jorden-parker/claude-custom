import type { ReviewStatus } from "./reviews";

const headerLabels: Record<ReviewStatus, string> = {
  ok: "done",
  error: "failed",
  running: "running",
  stopped: "stopped",
};

const textClasses: Record<ReviewStatus, string> = {
  ok: "border-green-600 text-green-700 dark:text-green-400",
  error: "border-red-600 text-red-700 dark:text-red-400",
  running: "border-blue-600 text-blue-700 dark:text-blue-400",
  stopped: "text-muted-foreground",
};

const dotClasses: Record<ReviewStatus, string> = {
  ok: "bg-green-500",
  error: "bg-red-500",
  running: "animate-pulse bg-blue-500",
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

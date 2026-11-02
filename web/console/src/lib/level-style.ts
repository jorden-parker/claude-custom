export type Level = "ok" | "warn" | "fail" | "error" | "info";

const textClasses: Record<Level, string> = {
  ok: "text-success-foreground",
  warn: "text-warning-foreground",
  fail: "text-error-foreground",
  error: "text-error-foreground",
  info: "text-info-foreground",
};

const boxClasses: Record<Level, string> = {
  ok: "rounded-md border border-success-border bg-success px-4 py-3 text-sm",
  warn: "rounded-md border border-warning-border bg-warning px-4 py-3 text-sm",
  fail: "rounded-md border border-error-border bg-error px-4 py-3 text-sm",
  error: "rounded-md border border-error-border bg-error px-4 py-3 text-sm",
  info: "rounded-md border border-info-border bg-info px-4 py-3 text-sm",
};

export function levelTextClass(level: Level): string {
  return textClasses[level];
}

export function levelBoxClass(level: Level): string {
  return boxClasses[level];
}

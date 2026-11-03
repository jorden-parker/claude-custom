export type Level = "ok" | "warn" | "fail" | "error" | "info";

const textClasses: Record<Level, string> = {
  ok: "text-success-foreground",
  warn: "text-warning-foreground",
  fail: "text-error-foreground",
  error: "text-error-foreground",
  info: "text-info-foreground",
};

const boxClasses: Record<Level, string> = {
  ok: "border-success-border bg-success text-success-foreground",
  warn: "border-warning-border bg-warning text-warning-foreground",
  fail: "border-error-border bg-error text-error-foreground",
  error: "border-error-border bg-error text-error-foreground",
  info: "border-info-border bg-info text-info-foreground",
};

export function levelTextClass(level: Level): string {
  return textClasses[level];
}

export function levelBoxClass(level: Level): string {
  return boxClasses[level];
}

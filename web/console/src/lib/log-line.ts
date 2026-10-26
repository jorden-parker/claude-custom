export type LogLevel = "error" | "warn" | "info" | "debug";

const LEVEL_FIELD = /\blevel=(ERROR|WARN|INFO|DEBUG)\b/;

const levelNames: Record<string, LogLevel> = {
  ERROR: "error",
  WARN: "warn",
  INFO: "info",
  DEBUG: "debug",
};

export function logLevel(text: string): LogLevel | null {
  const match = LEVEL_FIELD.exec(text);
  if (match === null) {
    return null;
  }
  return levelNames[match[1]];
}

export type LogFrame = { text: string; level: LogLevel | null };

export function logFrame(lineNumber: number, line: string): string {
  const data = JSON.stringify({ text: line, level: logLevel(line) });
  return `id: ${lineNumber}\ndata: ${data}\n\n`;
}

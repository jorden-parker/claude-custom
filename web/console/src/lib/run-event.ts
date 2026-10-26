export type RunEvent = { kind: string; t?: number } & Record<string, unknown>;

export function parseRunEvent(line: string): RunEvent | null {
  try {
    const value: unknown = JSON.parse(line);
    return isRunEvent(value) ? value : null;
  } catch {
    return null;
  }
}

export function isRunEndLine(line: string): boolean {
  return parseRunEvent(line)?.kind === "end";
}

export function parseRunEvents(text: string): RunEvent[] {
  return text
    .split("\n")
    .map(parseRunEvent)
    .filter((event): event is RunEvent => event !== null);
}

function isRunEvent(value: unknown): value is RunEvent {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { kind?: unknown }).kind === "string"
  );
}

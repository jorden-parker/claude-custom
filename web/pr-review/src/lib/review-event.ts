export type ReviewEvent = { kind: string } & Record<string, unknown>;

export function parseReviewEvent(text: string): ReviewEvent | null {
  try {
    const value: unknown = JSON.parse(text);
    return isReviewEvent(value) ? value : null;
  } catch {
    return null;
  }
}

function isReviewEvent(value: unknown): value is ReviewEvent {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { kind?: unknown }).kind === "string"
  );
}

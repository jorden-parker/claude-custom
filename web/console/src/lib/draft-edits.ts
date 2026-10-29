import {
  editableFieldsOf,
  type Decoration,
  type Draft,
  type ReviewComment,
} from "./draft-schema";

export function replaceAt<T>(items: readonly T[], index: number, next: T): T[] {
  return items.map((item, position) => (position === index ? next : item));
}

export function removeAt<T>(items: readonly T[], index: number): T[] {
  return items.filter((_item, position) => position !== index);
}

export function blankComment(): ReviewComment {
  return { label: "issue", decorations: [], body: "" };
}

export function blankSection(): { heading: string; body: string } {
  return { heading: "", body: "" };
}

export function toggleDecoration(
  decorations: readonly Decoration[],
  decoration: Decoration,
): Decoration[] {
  return decorations.includes(decoration)
    ? decorations.filter((item) => item !== decoration)
    : [...decorations, decoration];
}

export function pathFromInput(text: string): string | undefined {
  const trimmed = text.trim();
  return trimmed === "" ? undefined : trimmed;
}

export function lineFromInput(text: string): number | undefined {
  const line = Number(text);
  return text.trim() !== "" && Number.isInteger(line) && line > 0
    ? line
    : undefined;
}

export function isDirty(current: Draft, saved: Draft): boolean {
  return (
    JSON.stringify(editableFieldsOf(current)) !==
    JSON.stringify(editableFieldsOf(saved))
  );
}

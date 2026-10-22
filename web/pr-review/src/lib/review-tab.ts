export type ReviewTab = "findings" | "transcript";

export function tabFromValue(value: string): ReviewTab {
  return value === "transcript" ? "transcript" : "findings";
}

export function tabFromHash(hash: string): ReviewTab {
  return tabFromValue(hash.replace(/^#/, ""));
}

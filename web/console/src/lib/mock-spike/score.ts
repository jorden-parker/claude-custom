import { createSpecStreamCompiler } from "@json-render/core";
import { mockCatalog } from "./catalog.ts";

export type ReplyScore = {
  lines: number;
  patches: number;
  prose: number;
  elements: number;
  unknownTypes: string[];
  valid: boolean;
  issue: string | null;
};

type SpecElement = { type?: unknown };
type Spec = { root?: unknown; elements?: Record<string, SpecElement> };

export function isPatchLine(line: string): boolean {
  try {
    const value = JSON.parse(line);
    return (
      typeof value === "object" &&
      value !== null &&
      typeof value.op === "string" &&
      typeof value.path === "string"
    );
  } catch {
    return false;
  }
}

function unknownTypesIn(spec: Spec): string[] {
  const known = new Set<string>(mockCatalog.componentNames);
  const types = Object.values(spec.elements ?? {}).map((element) =>
    String(element.type),
  );
  return [...new Set(types.filter((type) => !known.has(type)))];
}

function firstIssue(spec: Spec): string | null {
  const result = mockCatalog.validate(spec);
  if (result.success) return null;
  const issue = result.error?.issues?.[0];
  if (!issue) return "invalid spec";
  return `${issue.path.join("/")}: ${issue.message}`;
}

export function scoreReply(reply: string): ReplyScore {
  const lines = reply
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  const patches = lines.filter(isPatchLine).length;
  const compiler = createSpecStreamCompiler<Spec>();
  compiler.push(lines.filter(isPatchLine).join("\n") + "\n");
  const spec = compiler.getResult() ?? {};
  const elements = Object.keys(spec.elements ?? {}).length;
  const issue = elements === 0 ? "no elements" : firstIssue(spec);
  return {
    lines: lines.length,
    patches,
    prose: lines.length - patches,
    elements,
    unknownTypes: unknownTypesIn(spec),
    valid: issue === null,
    issue,
  };
}

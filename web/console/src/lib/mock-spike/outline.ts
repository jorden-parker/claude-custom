import type { Spec } from "@json-render/core";

type Element = {
  type: string;
  props?: Record<string, unknown>;
  children?: string[];
};

export function specOutline(spec: Spec): string[] {
  const elements = (spec.elements ?? {}) as Record<string, Element>;
  if (!spec.root || !(spec.root in elements)) return [];
  return outlineFrom(elements, spec.root, 0, new Set());
}

function outlineFrom(
  elements: Record<string, Element>,
  key: string,
  depth: number,
  seen: Set<string>,
): string[] {
  const element = elements[key];
  if (!element || seen.has(key)) return [];
  seen.add(key);
  const line = `${"  ".repeat(depth)}${element.type}${describeProps(element.props ?? {})}`;
  const children = (element.children ?? []).flatMap((child) =>
    outlineFrom(elements, child, depth + 1, seen),
  );
  return [line, ...children];
}

function describeProps(props: Record<string, unknown>): string {
  const entries = Object.entries(props).map(
    ([name, value]) => `${name}=${JSON.stringify(value)}`,
  );
  return entries.length ? ` ${entries.join(" ")}` : "";
}

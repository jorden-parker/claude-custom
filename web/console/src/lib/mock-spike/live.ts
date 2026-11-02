import { createSpecStreamCompiler, type Spec } from "@json-render/core";
import { isPatchLine } from "./score.ts";

export const RUN_MARKER = "=== run ";
export const PRESET_MARKER = "preset: ";

export type LiveCell = { label: string; patches: number; spec: Spec };

const EMPTY_SPEC: Spec = { root: "", elements: {} };

export function liveCellsFrom(lines: readonly string[]): LiveCell[] {
  const cells: { label: string; patchLines: string[] }[] = [];
  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith(RUN_MARKER)) {
      cells.push({ label: line.slice(RUN_MARKER.length), patchLines: [] });
    } else if (cells.length > 0 && isPatchLine(line)) {
      cells[cells.length - 1].patchLines.push(line);
    }
  }
  return cells.map((cell) => ({
    label: cell.label,
    patches: cell.patchLines.length,
    spec: compile(cell.patchLines),
  }));
}

export function livePresetFrom(lines: readonly string[]): string | null {
  const line = lines.find((raw) => raw.trim().startsWith(PRESET_MARKER));
  return line ? line.trim().slice(PRESET_MARKER.length) : null;
}

function compile(patchLines: string[]): Spec {
  if (patchLines.length === 0) return EMPTY_SPEC;
  const compiler = createSpecStreamCompiler<Spec>();
  compiler.push(patchLines.join("\n") + "\n");
  const result = compiler.getResult();
  return {
    ...result,
    root: result?.root ?? EMPTY_SPEC.root,
    elements: result?.elements ?? EMPTY_SPEC.elements,
  };
}

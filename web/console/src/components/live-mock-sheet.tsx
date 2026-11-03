"use client";

import { useMemo } from "react";
import { useRunStream } from "@/components/use-run-stream";
import {
  liveCellsFrom,
  livePresetFrom,
  type LiveCell,
} from "@/lib/mock-spike/live.ts";
import { specOutline } from "@/lib/mock-spike/outline.ts";
import { MockFrame } from "@/lib/mock-spike/registry.tsx";
import { ScrollArea } from "@/components/ui/scroll-area";

export function LiveMockSheet({
  lines,
  running,
}: {
  lines: readonly string[];
  running: boolean;
}) {
  const cells = useMemo(() => liveCellsFrom(lines), [lines]);
  const preset = useMemo(() => livePresetFrom(lines), [lines]);
  if (cells.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        {running
          ? "Waiting for the first patch..."
          : "No mockup patches in this run."}
      </p>
    );
  }
  return (
    <div className="flex flex-col gap-4">
      {cells.map((cell, index) => (
        <LiveCellView
          key={cell.label}
          cell={cell}
          growing={running && index === cells.length - 1}
          preset={preset}
        />
      ))}
    </div>
  );
}

export function LiveMockRun({ id }: { id: string }) {
  const state = useRunStream(id);
  return (
    <LiveMockSheet
      lines={state.lines.map((line) => line.text)}
      running={state.ended === null}
    />
  );
}

function LiveCellView({
  cell,
  growing,
  preset,
}: {
  cell: LiveCell;
  growing: boolean;
  preset: string | null;
}) {
  const outline = specOutline(cell.spec);
  return (
    <article className="flex flex-col gap-3 rounded-lg border bg-card p-4">
      <header className="flex items-baseline justify-between gap-2 text-sm">
        <span className="font-medium">run {cell.label}</span>
        <span className="text-muted-foreground">
          {cell.patches} patches{growing ? ", streaming" : ""}
        </span>
      </header>
      {cell.spec.root ? <MockFrame spec={cell.spec} preset={preset} /> : null}
      <ScrollArea className="rounded-md bg-muted">
        <pre className="max-w-full p-2 text-xs">
          {outline.join("\n") || "no elements yet"}
        </pre>
      </ScrollArea>
    </article>
  );
}

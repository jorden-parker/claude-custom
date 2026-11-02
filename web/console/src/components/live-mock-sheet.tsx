"use client";

import { JSONUIProvider, Renderer } from "@json-render/react";
import { useMemo } from "react";
import { useRunStream } from "@/components/use-run-stream";
import { liveCellsFrom, type LiveCell } from "@/lib/mock-spike/live.ts";
import { specOutline } from "@/lib/mock-spike/outline.ts";
import { mockRegistry } from "@/lib/mock-spike/registry.tsx";

export function LiveMockSheet({
  lines,
  running,
}: {
  lines: readonly string[];
  running: boolean;
}) {
  const cells = useMemo(() => liveCellsFrom(lines), [lines]);
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

function LiveCellView({ cell, growing }: { cell: LiveCell; growing: boolean }) {
  const outline = specOutline(cell.spec);
  return (
    <article className="flex flex-col gap-3 rounded-lg border border-ink bg-card p-4">
      <header className="flex items-baseline justify-between gap-2 text-sm">
        <span className="font-medium">run {cell.label}</span>
        <span className="text-muted-foreground">
          {cell.patches} patches{growing ? ", streaming" : ""}
        </span>
      </header>
      <div className="rounded-md bg-background p-4">
        {cell.spec.root ? (
          <JSONUIProvider registry={mockRegistry}>
            <Renderer spec={cell.spec} registry={mockRegistry} />
          </JSONUIProvider>
        ) : null}
      </div>
      <pre className="overflow-x-auto rounded-md bg-muted p-2 text-xs">
        {outline.join("\n") || "no elements yet"}
      </pre>
    </article>
  );
}

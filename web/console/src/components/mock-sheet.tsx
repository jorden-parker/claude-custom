"use client";

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { ChevronDownIcon } from "lucide-react";
import { MockFrame } from "@/lib/mock-spike/registry.tsx";
import { specOutline } from "@/lib/mock-spike/outline.ts";
import type { MockRun, MockSpikeReport } from "@/lib/mock-spike/reports.ts";

export function MockSheet({ report }: { report: MockSpikeReport }) {
  return (
    <section className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        {report.model}, preset {report.preset ?? "unknown"}, verdict{" "}
        {report.verdict}, from {report.file}
      </p>
      <div className="grid gap-4 lg:grid-cols-2">
        {report.runs.map((run) => (
          <MockCell
            key={`${run.brief}-${run.run}`}
            run={run}
            preset={report.preset}
          />
        ))}
      </div>
    </section>
  );
}

function MockCell({ run, preset }: { run: MockRun; preset: string | null }) {
  return (
    <article className="flex flex-col gap-3 rounded-lg border bg-card p-4">
      <header className="flex items-baseline justify-between gap-2 text-sm">
        <span className="font-medium">
          {run.brief} #{run.run}
        </span>
        <span className="text-muted-foreground">
          {run.score.patches}/{run.score.lines} patch lines,{" "}
          {run.score.elements} elements
        </span>
      </header>
      {run.score.propIssue ? (
        <p className="text-sm text-warning-foreground">
          Prop outside the catalog: {run.score.propIssue}
        </p>
      ) : null}
      {run.score.issue === null ? (
        <MockFrame spec={run.spec} preset={preset} />
      ) : (
        <p className="text-sm text-destructive">
          Not rendered: {run.score.issue}
        </p>
      )}
      <Collapsible className="text-xs">
        <CollapsibleTrigger className="group flex cursor-pointer items-center gap-2 text-muted-foreground">
          <ChevronDownIcon className="size-4 shrink-0 transition-transform group-data-[panel-open]:rotate-180" />
          Elements the model produced
        </CollapsibleTrigger>
        <CollapsibleContent keepMounted>
          <div className="mt-2 rounded-md bg-muted">
            <pre className="max-w-full whitespace-pre-wrap p-2 [overflow-wrap:anywhere]">
              {specOutline(run.spec).join("\n") || "none"}
            </pre>
          </div>
        </CollapsibleContent>
      </Collapsible>
    </article>
  );
}

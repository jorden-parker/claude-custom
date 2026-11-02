"use client";

import { MockFrame } from "@/lib/mock-spike/registry.tsx";
import { specOutline } from "@/lib/mock-spike/outline.ts";
import type { MockRun, MockSpikeReport } from "@/lib/mock-spike/reports.ts";

export function MockSheet({ report }: { report: MockSpikeReport }) {
  return (
    <section className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">
        {report.model}, verdict {report.verdict}, from {report.file}
      </p>
      <div className="grid gap-4 lg:grid-cols-2">
        {report.runs.map((run) => (
          <MockCell key={`${run.brief}-${run.run}`} run={run} />
        ))}
      </div>
    </section>
  );
}

function MockCell({ run }: { run: MockRun }) {
  return (
    <article className="flex flex-col gap-3 rounded-lg border border-ink bg-card p-4">
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
        <MockFrame spec={run.spec} />
      ) : (
        <p className="text-sm text-destructive">
          Not rendered: {run.score.issue}
        </p>
      )}
      <details className="text-xs">
        <summary className="cursor-pointer text-muted-foreground">
          Elements the model produced
        </summary>
        <pre className="mt-2 overflow-x-auto rounded-md bg-muted p-2">
          {specOutline(run.spec).join("\n") || "none"}
        </pre>
      </details>
    </article>
  );
}

"use client";

import Link from "next/link";
import { useState } from "react";
import { RunOutputBox } from "@/components/run-view";
import { StartRunButton } from "@/components/start-run-button";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useRunStream } from "@/components/use-run-stream";
import { parseWhyReport, type WhyReport } from "@/lib/diagnose";
import type { RunState } from "@/lib/run-state";

const WHY_COMMAND = "why";

export function WhyCard({ initialRunId }: { initialRunId: string | null }) {
  const [runId, setRunId] = useState(initialRunId);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Why did the last run go wrong?</CardTitle>
        <CardDescription>
          Reads the proxy log and the incidents file and names one cause, its
          evidence and one fix
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <StartRunButton
          command={WHY_COMMAND}
          params={{}}
          stay
          onStarted={setRunId}
        >
          Explain the last run
        </StartRunButton>
        {runId === null ? (
          <p className="text-sm text-muted-foreground">No why run yet.</p>
        ) : (
          <WhyRunResult key={runId} id={runId} />
        )}
      </CardContent>
    </Card>
  );
}

function WhyRunResult({ id }: { id: string }) {
  const state = useRunStream(id);
  const [raw, setRaw] = useState(false);
  const report =
    state.ended === null
      ? null
      : parseWhyReport(state.lines.map((line) => line.text));
  const showLines = state.ended === null || raw || report === null;
  return (
    <div className="flex flex-col gap-3">
      {report === null ? null : <WhyReportView report={report} />}
      {state.ended !== null && report === null ? (
        <p className="text-sm text-error-foreground">
          The run printed no report (exit {state.ended.code}).
        </p>
      ) : null}
      {showLines ? <RunOutputBox lines={state.lines} live={state.ended === null} /> : null}
      <RunLinks
        id={id}
        state={state}
        raw={raw}
        onToggleRaw={() => setRaw(!raw)}
      />
    </div>
  );
}

function WhyReportView({ report }: { report: WhyReport }) {
  return (
    <dl className="flex flex-col gap-2 text-sm">
      <div>
        <dt className="text-xs text-muted-foreground">Verdict</dt>
        <dd aria-label="verdict" className="font-medium">
          {report.verdict}: {report.summary} ({report.window})
        </dd>
      </div>
      <div>
        <dt className="text-xs text-muted-foreground">Evidence</dt>
        <dd aria-label="evidence">{report.evidence}</dd>
      </div>
      <div>
        <dt className="text-xs text-muted-foreground">Fix</dt>
        <dd>
          <code
            aria-label="fix"
            className="block whitespace-pre-wrap break-all rounded-lg bg-muted/40 p-2"
          >
            {report.fix}
          </code>
        </dd>
      </div>
      <div>
        <dt className="text-xs text-muted-foreground">Prefix</dt>
        <dd aria-label="prefix hit rate">
          {report.prefix.percent}% of {report.prefix.requests} requests stable
          through tools
        </dd>
      </div>
    </dl>
  );
}

function RunLinks({
  id,
  state,
  raw,
  onToggleRaw,
}: {
  id: string;
  state: RunState;
  raw: boolean;
  onToggleRaw: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {state.ended === null ? null : (
        <Button variant="outline" size="sm" onClick={onToggleRaw}>
          {raw ? "Report" : "Raw output"}
        </Button>
      )}
      <Link
        className={buttonVariants({ variant: "outline", size: "sm" })}
        href={`/runs/${encodeURIComponent(id)}`}
      >
        Open run
      </Link>
    </div>
  );
}

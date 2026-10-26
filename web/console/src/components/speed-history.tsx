"use client";

import Link from "next/link";
import { useState } from "react";
import { StartRunButton } from "@/components/start-run-button";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import type { SpeedCheckFailure } from "@/lib/speed-failures";
import type { SpeedReport } from "@/lib/speed-reports";

const COPIED_MS = 1500;

type SpeedHistoryProps = { reports: SpeedReport[]; failures: SpeedCheckFailure[] };

export function SpeedHistory({ reports, failures }: SpeedHistoryProps) {
  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3">
        <StartRunButton command="speed-check" params={{}}>
          Run speed check
        </StartRunButton>
        <p className="text-sm text-muted-foreground">
          It pulls up to four sizes, needs AC power and about 45 GB free, and takes a long time. The run page shows
          its six stages.
        </p>
      </section>
      {failures.map((failure) => (
        <FailureCard key={failure.id} failure={failure} />
      ))}
      {reports.length === 0 ? (
        <p className="text-sm text-muted-foreground">No speed-check reports in ~/bench-results yet.</p>
      ) : (
        reports.map((report) => <ReportCard key={report.file} report={report} />)
      )}
    </div>
  );
}

function FailureCard({ failure }: { failure: SpeedCheckFailure }) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-2 text-sm">
        <span className="font-medium text-red-700 dark:text-red-400">Speed check failed · {failure.startedAt}</span>
        <p className="font-mono text-xs">{failure.stoppedLine ?? "No stopped line was printed."}</p>
        <Link href={`/runs/${encodeURIComponent(failure.id)}`} className="text-xs underline">
          Open run
        </Link>
      </CardContent>
    </Card>
  );
}

function ReportCard({ report }: { report: SpeedReport }) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="font-mono text-sm">{report.at}</span>
          <CopyPasteBlock report={report} />
        </div>
        <pre className="whitespace-pre-wrap font-mono text-xs">{report.verdict.join("\n")}</pre>
        <p className="text-sm font-semibold">{report.next}</p>
      </CardContent>
    </Card>
  );
}

function CopyPasteBlock({ report }: { report: SpeedReport }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    const block = ["speed-check results", ...report.verdict, `full report: ~/bench-results/${report.file}`].join("\n");
    await navigator.clipboard.writeText(block);
    setCopied(true);
    setTimeout(() => setCopied(false), COPIED_MS);
  };

  return (
    <Button variant="outline" size="sm" onClick={() => void copy()}>
      {copied ? "Copied" : "Copy paste block"}
    </Button>
  );
}

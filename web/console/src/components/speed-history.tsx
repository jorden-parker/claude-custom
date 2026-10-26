"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { StartRunButton } from "@/components/start-run-button";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import type { RunSummary } from "@/lib/run-log";
import type { SpeedReport } from "@/lib/speed-reports";

const COPIED_MS = 1500;

export function SpeedHistory() {
  const history = useSpeedHistory();
  if (history === null) {
    return <p className="text-sm text-muted-foreground">Loading past verdicts...</p>;
  }
  const { reports, failures } = history;
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

function useSpeedHistory(): { reports: SpeedReport[]; failures: RunSummary[] } | null {
  const [history, setHistory] = useState<{ reports: SpeedReport[]; failures: RunSummary[] } | null>(null);
  useEffect(() => {
    const load = async () => {
      const [reportsResponse, runsResponse] = await Promise.all([
        fetch("/api/speed-reports", { cache: "no-store" }),
        fetch("/api/runs", { cache: "no-store" }),
      ]);
      const reports = (await reportsResponse.json()) as SpeedReport[];
      const runs = (await runsResponse.json()) as RunSummary[];
      const failures = runs.filter((run) => run.command === "speed-check" && run.status === "failed");
      setHistory({ reports, failures });
    };
    void load();
  }, []);
  return history;
}

function FailureCard({ failure }: { failure: RunSummary }) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-2 text-sm">
        <span className="font-medium text-red-700 dark:text-red-400">Speed check failed · {failure.startedAt}</span>
        <p className="text-xs text-muted-foreground">The run page shows its "speed-check stopped" line.</p>
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

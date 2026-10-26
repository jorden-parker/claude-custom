"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { formatLocalTime, formatRelative } from "@/lib/format-time";
import type { RunSummary } from "@/lib/run-log";
import { runStatusDotClass, runStatusLabel, runStatusTextClass } from "@/lib/run-status-style";

const POLL_INTERVAL_MS = 2000;

export function RunList() {
  const [runs, setRuns] = useState<RunSummary[] | null>(null);
  const [now, setNow] = useState(0);

  useEffect(() => {
    const load = async () => {
      const response = await fetch("/api/runs", { cache: "no-store" });
      if (response.ok) {
        setRuns((await response.json()) as RunSummary[]);
        setNow(Date.now());
      }
    };
    void load();
    const timer = setInterval(load, POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  }, []);

  if (runs === null) {
    return <p className="text-sm text-muted-foreground">Loading runs...</p>;
  }
  if (runs.length === 0) {
    return <p className="text-sm text-muted-foreground">No runs yet. Start one above.</p>;
  }
  return (
    <ul className="flex flex-col gap-3">
      {runs.map((run) => (
        <li key={run.id} className="animate-in fade-in slide-in-from-top-1">
          <RunRow run={run} now={now} />
        </li>
      ))}
    </ul>
  );
}

function RunRow({ run, now }: { run: RunSummary; now: number }) {
  return (
    <Link
      href={`/runs/${encodeURIComponent(run.id)}`}
      className="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <Card className="cursor-pointer transition-colors hover:bg-muted/60">
        <CardContent className="flex flex-col gap-2">
          <div className="flex min-w-0 items-center gap-2">
            <span className={runStatusDotClass(run.status)} />
            <span className="min-w-0 break-words font-medium">{run.label || run.id}</span>
          </div>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <Badge variant="outline" className={runStatusTextClass(run.status)}>
              {runStatusLabel(run.status)}
            </Badge>
            {run.seconds === null ? null : <span>{Math.round(run.seconds)}s</span>}
            <time dateTime={run.startedAt} title={run.startedAt}>
              {formatLocalTime(run.startedAt)}
              {now === 0 ? "" : ` · ${formatRelative(run.startedAt, now)}`}
            </time>
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}

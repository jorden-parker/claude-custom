"use client";

import Link from "next/link";
import { StartRunButton } from "@/components/start-run-button";
import { useRunSummaries } from "@/components/use-run-summaries";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { CHECK_COMMANDS, type CheckCommand } from "@/lib/check-commands";
import { formatRelative } from "@/lib/format-time";
import type { RunSummary } from "@/lib/run-log";
import {
  runStatusDotClass,
  runStatusLabel,
  runStatusTextClass,
} from "@/lib/run-status-style";

const RUNS_POLL_INTERVAL_MS = 2000;

export function latestRunFor(
  runs: RunSummary[],
  check: CheckCommand,
  size: string,
): RunSummary | undefined {
  return runs.find(
    (run) =>
      run.command === check.command &&
      (!check.needsSize || run.label.includes(`(${size})`)),
  );
}

export function CheckCards({ size }: { size: string }) {
  const { runs, now } = useRunSummaries(RUNS_POLL_INTERVAL_MS);
  const extraChecks = CHECK_COMMANDS.filter(
    (check) => check.command !== "doctor",
  );
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {extraChecks.map((check) => (
        <CheckCardItem
          key={check.command}
          check={check}
          size={size}
          runs={runs}
          now={now}
        />
      ))}
    </div>
  );
}

function CheckCardItem({
  check,
  size,
  runs,
  now,
}: {
  check: CheckCommand;
  size: string;
  runs: RunSummary[] | null;
  now: number;
}) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-2">
        <span className="font-medium">{check.title}</span>
        <span className="text-sm text-muted-foreground">
          {check.description}
        </span>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <StartRunButton
            command={check.command}
            params={check.needsSize ? { size } : {}}
          >
            Run
          </StartRunButton>
          {runs === null ? (
            <Skeleton className="h-5 w-24" />
          ) : (
            <LatestRunStatus run={latestRunFor(runs, check, size)} now={now} />
          )}
        </div>
      </CardContent>
    </Card>
  );
}

function LatestRunStatus({
  run,
  now,
}: {
  run: RunSummary | undefined;
  now: number;
}) {
  if (run === undefined) {
    return <span className="text-sm text-muted-foreground">Never run</span>;
  }
  return (
    <div className="flex items-center gap-2 text-sm">
      <Badge variant="outline" className={runStatusTextClass(run.status)}>
        <span className={runStatusDotClass(run.status)} />
        {runStatusLabel(run.status)}
      </Badge>
      <time dateTime={run.startedAt} className="text-muted-foreground">
        {formatRelative(run.startedAt, now)}
      </time>
      <Link href={`/runs/${encodeURIComponent(run.id)}`} className="underline">
        View run
      </Link>
    </div>
  );
}

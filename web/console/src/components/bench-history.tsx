import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { formatLocalTime } from "@/lib/format-time";
import type { RunSummary } from "@/lib/run-log";
import { runStatusDotClass, runStatusLabel, runStatusTextClass } from "@/lib/run-status-style";

type BenchHistoryProps = { runs: readonly RunSummary[] };

export function BenchHistory({ runs }: BenchHistoryProps) {
  if (runs.length === 0) {
    return <p className="text-sm text-muted-foreground">No bench runs yet.</p>;
  }
  return (
    <ul className="flex flex-col gap-2">
      {runs.map((run) => (
        <li key={run.id}>
          <Link
            href={`/runs/${encodeURIComponent(run.id)}`}
            className="flex min-w-0 flex-wrap items-center gap-2 rounded-md px-2 py-1 text-sm hover:bg-muted/60"
          >
            <span className={runStatusDotClass(run.status)} />
            <span className="min-w-0 break-words">{run.label || run.id}</span>
            <Badge variant="outline" className={runStatusTextClass(run.status)}>
              {runStatusLabel(run.status)}
            </Badge>
            <time className="text-xs text-muted-foreground" dateTime={run.startedAt}>
              {formatLocalTime(run.startedAt)}
            </time>
          </Link>
        </li>
      ))}
    </ul>
  );
}

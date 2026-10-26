"use client";

import Link from "next/link";
import { useState } from "react";
import { ConfigCard } from "@/components/config-card";
import { DoctorRunChecklist } from "@/components/doctor-checklist";
import { SizeSelect, useSizePicker } from "@/components/size-select";
import { StartRunButton } from "@/components/start-run-button";
import { useRunSummaries } from "@/components/use-run-summaries";
import { formatLocalTime } from "@/lib/format-time";
import type { RunSummary } from "@/lib/run-log";
import { runStatusDotClass, runStatusLabel } from "@/lib/run-status-style";

const RUNS_POLL_INTERVAL_MS = 2000;
const HISTORY_LENGTH = 10;

export function HealthView() {
  const { sizes, size, select } = useSizePicker();
  const { runs } = useRunSummaries(RUNS_POLL_INTERVAL_MS);
  return (
    <>
      <SizeSelect sizes={sizes} size={size} onChange={select} />
      {size === "" ? null : <SizePanels key={size} size={size} runs={runs ?? []} />}
    </>
  );
}

function SizePanels({ size, runs }: { size: string; runs: RunSummary[] }) {
  const [startedId, setStartedId] = useState<string | null>(null);
  const history = doctorRunsFor(runs, size);
  const shownId = startedId ?? history[0]?.id ?? null;
  return (
    <>
      <ConfigCard size={size} />
      <ChecksSection size={size} shownId={shownId} onStarted={setStartedId} />
      <HistorySection runs={history} />
    </>
  );
}

function doctorRunsFor(runs: RunSummary[], size: string): RunSummary[] {
  return runs.filter((run) => run.command === "doctor" && run.label.includes(`(${size})`)).slice(0, HISTORY_LENGTH);
}

function ChecksSection({
  size,
  shownId,
  onStarted,
}: {
  size: string;
  shownId: string | null;
  onStarted: (id: string) => void;
}) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">Checks</h2>
        <StartRunButton command="doctor" params={{ size }} stay onStarted={onStarted}>
          Run checks
        </StartRunButton>
      </div>
      {shownId === null ? (
        <p className="text-sm text-muted-foreground">No checks run for {size} yet.</p>
      ) : (
        <DoctorRunChecklist key={shownId} id={shownId} />
      )}
    </section>
  );
}

function HistorySection({ runs }: { runs: RunSummary[] }) {
  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-lg font-semibold">History</h2>
      {runs.length === 0 ? (
        <p className="text-sm text-muted-foreground">No doctor runs yet.</p>
      ) : (
        <ul className="flex flex-col gap-2 text-sm">
          {runs.map((run) => (
            <HistoryRow key={run.id} run={run} />
          ))}
        </ul>
      )}
    </section>
  );
}

function HistoryRow({ run }: { run: RunSummary }) {
  return (
    <li>
      <Link href={`/runs/${encodeURIComponent(run.id)}`} className="flex items-center gap-2 underline">
        <span className={runStatusDotClass(run.status)} />
        <span>{runStatusLabel(run.status)}</span>
        <time dateTime={run.startedAt}>{formatLocalTime(run.startedAt)}</time>
      </Link>
    </li>
  );
}

"use client";

import Link from "next/link";
import { Loader2 } from "lucide-react";
import { useEffect, useState } from "react";
import { DoctorChecklist } from "@/components/doctor-checklist";
import { LiveMockSheet } from "@/components/live-mock-sheet";
import { StreamOutput } from "@/components/stream-output";
import { useRunStream } from "@/components/use-run-stream";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { checksFromLines } from "@/lib/doctor-checks";
import { percentFrom, phaseFrom } from "@/lib/pull-progress";
import { elapsedSeconds, formatElapsed, statusOf } from "@/lib/run-display";
import type { RunStatus, RunSummary } from "@/lib/run-log";
import type { RunState } from "@/lib/run-state";
import { runStatusLabel, runStatusTextClass } from "@/lib/run-status-style";
import { PetalBurst } from "@/components/petal-burst";
import { ProgressBar } from "@/components/progress-bar";

const TICK_MS = 1000;
const STATUS_POLL_MS = 2000;
const CHECKLIST_COMMANDS = new Set([
  "doctor",
  "qwen-doctor",
  "models-outdated",
]);
const MOCK_SPIKE_COMMAND = "mock-spike";

type RunViewProps = { id: string };

export function RunView({ id }: RunViewProps) {
  const state = useRunStream(id);
  const serverStatus = useServerStatus(id, state.ended !== null);
  const now = useNow(state.ended !== null);

  const status = statusOf(state, serverStatus);

  return (
    <div className="flex flex-col gap-4">
      <RunHeader
        id={id}
        label={labelOf(state)}
        status={status}
        seconds={elapsedSeconds(state, now)}
        reviewId={state.reviewId}
      />
      {state.stage === null ? null : <StageBar stage={state.stage} />}
      <ProgressLines progress={state.progress} />
      {state.header?.command === MOCK_SPIKE_COMMAND ? (
        <LiveMockSheet
          lines={state.lines.map((line) => line.text)}
          running={state.ended === null}
        />
      ) : null}
      {isChecklistRun(state) ? (
        <ChecklistOutput state={state} />
      ) : (
        <RunOutputBox lines={state.lines} />
      )}
      {state.ended === null ? null : (
        <EndBanner status={status} code={state.ended.code} />
      )}
    </div>
  );
}

function isChecklistRun(state: RunState): boolean {
  return state.header !== null && CHECKLIST_COMMANDS.has(state.header.command);
}

function ChecklistOutput({ state }: { state: RunState }) {
  const output = checksFromLines(state.lines.map((line) => line.text));
  return (
    <Card>
      <CardContent>
        <DoctorChecklist
          checks={output.checks}
          other={output.other}
          running={state.ended === null}
        />
      </CardContent>
    </Card>
  );
}

function labelOf(state: RunState): string {
  return state.header === null ? "" : state.header.label;
}

function RunHeader({
  id,
  label,
  status,
  seconds,
  reviewId,
}: {
  id: string;
  label: string;
  status: RunStatus;
  seconds: number;
  reviewId: string | null;
}) {
  return (
    <header className="flex flex-wrap items-center gap-3">
      <h1 className="min-w-0 break-words text-xl font-semibold">
        {label || id}
      </h1>
      <Badge variant="outline" className={runStatusTextClass(status)}>
        {runStatusLabel(status)}
      </Badge>
      <span className="font-mono text-sm tabular-nums text-muted-foreground">
        {formatElapsed(seconds)}
      </span>
      {status === "running" ? (
        <Button variant="outline" size="sm" onClick={() => void cancelRun(id)}>
          Cancel
        </Button>
      ) : null}
      {reviewId === null ? null : (
        <Link
          className={buttonVariants({ variant: "outline", size: "sm" })}
          href={`/reviews/${encodeURIComponent(reviewId)}`}
        >
          Open review
        </Link>
      )}
    </header>
  );
}

export function RunOutputBox({ lines }: { lines: RunState["lines"] }) {
  return (
    <StreamOutput
      lines={lines.map((line, index) => ({
        key: index,
        text: line.text,
        className: line.stream === "stderr" ? "text-muted-foreground" : "",
      }))}
    />
  );
}

function StageBar({ stage }: { stage: NonNullable<RunState["stage"]> }) {
  const percent =
    stage.total === 0 ? 0 : Math.min(100, (stage.number / stage.total) * 100);
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm">
        Stage {stage.number} of {stage.total} — {stage.title}
      </p>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
        <div
          className="h-full rounded-full bg-info-foreground transition-[width] duration-500"
          style={{ width: `${percent}%` }}
        />
      </div>
    </div>
  );
}

function ProgressLines({ progress }: { progress: RunState["progress"] }) {
  const texts = [progress.stdout, progress.stderr].filter(
    (text): text is string => text !== undefined,
  );
  const measured = measuredProgress(texts);
  if (measured !== null) {
    return (
      <ProgressBar
        percent={measured.percent}
        phase={phaseFrom(measured.text)}
        text={measured.text}
      />
    );
  }
  if (texts.length === 0) {
    return null;
  }
  return (
    <div className="flex flex-col gap-1 text-sm text-muted-foreground">
      {texts.map((text, index) => (
        <p key={index} className="flex items-center gap-2 font-mono text-xs">
          <Loader2 className="size-3 animate-spin" />
          {text}
        </p>
      ))}
    </div>
  );
}

function measuredProgress(
  texts: string[],
): { percent: number; text: string } | null {
  for (const text of texts) {
    const percent = percentFrom(text);
    if (percent !== null) {
      return { percent, text };
    }
  }
  return null;
}

function EndBanner({ status, code }: { status: RunStatus; code: number }) {
  return (
    <Card className="relative">
      <PetalBurst status={status} />
      <CardContent
        className={`text-sm font-medium ${runStatusTextClass(status)}`}
      >
        {runStatusLabel(status)}
        {status === "failed" ? ` (exit ${code})` : ""}
      </CardContent>
    </Card>
  );
}

function useNow(stopped: boolean): number {
  const [now, setNow] = useState(0);
  useEffect(() => {
    if (stopped) {
      return;
    }
    const timer = setInterval(() => setNow(Date.now()), TICK_MS);
    return () => clearInterval(timer);
  }, [stopped]);
  return now;
}

function useServerStatus(id: string, stopped: boolean): RunStatus | null {
  const [status, setStatus] = useState<RunStatus | null>(null);
  useEffect(() => {
    if (stopped) {
      return;
    }
    const load = async () => {
      const response = await fetch("/api/runs", { cache: "no-store" });
      if (response.ok) {
        const runs = (await response.json()) as RunSummary[];
        setStatus(runs.find((run) => run.id === id)?.status ?? null);
      }
    };
    void load();
    const timer = setInterval(load, STATUS_POLL_MS);
    return () => clearInterval(timer);
  }, [id, stopped]);
  return status;
}

async function cancelRun(id: string): Promise<void> {
  await fetch(`/api/runs/${encodeURIComponent(id)}/cancel`, { method: "POST" });
}

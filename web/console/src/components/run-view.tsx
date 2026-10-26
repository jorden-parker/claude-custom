"use client";

import { Loader2 } from "lucide-react";
import { useEffect, useReducer, useRef, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { parseRunEvent } from "@/lib/run-event";
import { elapsedSeconds, formatElapsed, reduceRunMessage, statusOf } from "@/lib/run-display";
import type { RunStatus, RunSummary } from "@/lib/run-log";
import { initialRunState, type RunState } from "@/lib/run-state";
import { runStatusLabel, runStatusTextClass } from "@/lib/run-status-style";

const TICK_MS = 1000;
const STATUS_POLL_MS = 2000;
const FOLLOW_THRESHOLD_PX = 8;

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
      />
      {state.stage === null ? null : <StageBar stage={state.stage} />}
      <ProgressLines progress={state.progress} />
      <OutputBox lines={state.lines} />
      {state.ended === null ? null : <EndBanner status={status} code={state.ended.code} />}
    </div>
  );
}

function useRunStream(id: string): RunState {
  const [state, dispatch] = useReducer(reduceRunMessage, initialRunState);
  useEffect(() => {
    const source = new EventSource(`/api/runs/${encodeURIComponent(id)}/events`);
    source.onmessage = (message) => {
      dispatch({ data: message.data, lastEventId: message.lastEventId });
      if (parseRunEvent(message.data)?.kind === "end") {
        source.close();
      }
    };
    return () => source.close();
  }, [id]);
  return state;
}

function labelOf(state: RunState): string {
  return state.header === null ? "" : state.header.label;
}

function RunHeader({ id, label, status, seconds }: { id: string; label: string; status: RunStatus; seconds: number }) {
  return (
    <header className="flex flex-wrap items-center gap-3">
      <h1 className="min-w-0 break-words text-xl font-semibold">{label || id}</h1>
      <Badge variant="outline" className={runStatusTextClass(status)}>
        {runStatusLabel(status)}
      </Badge>
      <span className="font-mono text-sm tabular-nums text-muted-foreground">{formatElapsed(seconds)}</span>
      {status === "running" ? (
        <Button variant="outline" size="sm" onClick={() => void cancelRun(id)}>
          Cancel
        </Button>
      ) : null}
    </header>
  );
}

function OutputBox({ lines }: { lines: RunState["lines"] }) {
  const outputRef = useRef<HTMLDivElement>(null);
  const followRef = useRef(true);

  useEffect(() => {
    const output = outputRef.current;
    if (output && followRef.current) {
      output.scrollTop = output.scrollHeight;
    }
  }, [lines.length]);

  return (
    <div
      ref={outputRef}
      onScroll={(event) => {
        followRef.current = isAtBottom(event.currentTarget);
      }}
      className="max-h-[60vh] overflow-auto rounded-lg bg-muted/40 p-3 font-mono text-xs"
    >
      {lines.map((line, index) => (
        <div key={index} className={lineClass(line.stream)}>
          {line.text}
        </div>
      ))}
    </div>
  );
}

function isAtBottom(box: HTMLDivElement): boolean {
  return box.scrollHeight - box.scrollTop - box.clientHeight < FOLLOW_THRESHOLD_PX;
}

function lineClass(stream: RunState["lines"][number]["stream"]): string {
  const color = stream === "stderr" ? "text-muted-foreground" : "";
  return `animate-in fade-in whitespace-pre-wrap break-all ${color}`;
}

function StageBar({ stage }: { stage: NonNullable<RunState["stage"]> }) {
  const percent = stage.total === 0 ? 0 : Math.min(100, (stage.number / stage.total) * 100);
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm">
        Stage {stage.number} of {stage.total} — {stage.title}
      </p>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full bg-blue-500 transition-[width] duration-500" style={{ width: `${percent}%` }} />
      </div>
    </div>
  );
}

function ProgressLines({ progress }: { progress: RunState["progress"] }) {
  const texts = [progress.stdout, progress.stderr].filter((text): text is string => text !== undefined);
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

function EndBanner({ status, code }: { status: RunStatus; code: number }) {
  return (
    <Card>
      <CardContent className={`text-sm font-medium ${runStatusTextClass(status)}`}>
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

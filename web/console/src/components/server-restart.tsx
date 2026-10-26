"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { RunView } from "@/components/run-view";
import type { RunStatus, RunSummary } from "@/lib/run-log";

const RUN_POLL_MS = 1000;
const PING_POLL_MS = 500;
const PING_DEADLINE_MS = 30_000;

type PingState = "restarting" | "back" | "timeout";

type RestartPhase = "running" | "failed" | PingState;

type ServerRestartProps = { runId: string; onBack: () => void };

export function ServerRestart({ runId, onBack }: ServerRestartProps) {
  const runStatus = useRunStatus(runId);
  const pingState = usePingState(runStatus, onBack);
  return (
    <section className="flex flex-col gap-3">
      <RunView id={runId} />
      <RestartNotice phase={phaseOf(runStatus, pingState)} />
    </section>
  );
}

function phaseOf(runStatus: RunStatus | null, pingState: PingState): RestartPhase {
  if (runStatus === null || runStatus === "running") {
    return "running";
  }
  return runStatus === "ok" ? pingState : "failed";
}

function useRunStatus(runId: string): RunStatus | null {
  const [status, setStatus] = useState<RunStatus | null>(null);
  useEffect(() => {
    if (status !== null && status !== "running") {
      return;
    }
    const check = async () => {
      const response = await fetch("/api/runs", { cache: "no-store" });
      if (!response.ok) {
        return;
      }
      const runs = (await response.json()) as RunSummary[];
      const found = runs.find((run) => run.id === runId)?.status;
      if (found !== undefined) {
        setStatus(found);
      }
    };
    void check();
    const timer = setInterval(check, RUN_POLL_MS);
    return () => clearInterval(timer);
  }, [runId, status]);
  return status;
}

function usePingState(runStatus: RunStatus | null, onBack: () => void): PingState {
  const [pingState, setPingState] = useState<PingState>("restarting");
  useEffect(() => {
    if (runStatus !== "ok") {
      return;
    }
    const deadline = Date.now() + PING_DEADLINE_MS;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const check = async () => {
      if (await isOllamaUp()) {
        setPingState("back");
        onBack();
        return;
      }
      if (Date.now() >= deadline) {
        setPingState("timeout");
        return;
      }
      timer = setTimeout(check, PING_POLL_MS);
    };
    void check();
    return () => clearTimeout(timer);
  }, [runStatus, onBack]);
  return pingState;
}

async function isOllamaUp(): Promise<boolean> {
  try {
    const response = await fetch("/api/server/ping", { cache: "no-store" });
    const body = (await response.json()) as { up: boolean };
    return body.up;
  } catch {
    return false;
  }
}

function RestartNotice({ phase }: { phase: RestartPhase }) {
  if (phase === "running") {
    return null;
  }
  if (phase === "failed") {
    return <p className="text-sm text-red-700 dark:text-red-400">The run did not finish, so Ollama was not restarted.</p>;
  }
  if (phase === "restarting") {
    return <p className="animate-pulse text-sm text-muted-foreground">Ollama restarting…</p>;
  }
  if (phase === "back") {
    return <p className="text-sm text-green-700 dark:text-green-400">Ollama is back up.</p>;
  }
  return (
    <p className="text-sm text-red-700 dark:text-red-400">
      Ollama did not come back in 30 s — see{" "}
      <Link href="/logs" className="underline">
        Logs
      </Link>
    </p>
  );
}

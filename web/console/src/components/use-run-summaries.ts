"use client";

import { useEffect, useState } from "react";
import type { RunSummary } from "@/lib/run-log";

export function useRunSummaries(pollIntervalMs: number): { runs: RunSummary[] | null; now: number } {
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
    const timer = setInterval(load, pollIntervalMs);
    return () => clearInterval(timer);
  }, [pollIntervalMs]);
  return { runs, now };
}

"use client";

import { Select } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { useState } from "react";
import { MarkdownText } from "@/components/markdown-text";
import { RunOutputBox } from "@/components/run-view";
import { StartRunButton } from "@/components/start-run-button";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { loadJson } from "@/components/use-fetched-json";
import { useRunStream } from "@/components/use-run-stream";
import { parseRescueSummary, type RescueSummary } from "@/lib/diagnose";
import type { RescueReport } from "@/lib/rescue-report";

const RESCUE_COMMAND = "rescue";
const LATEST_REPORT_URL = "/api/rescue/latest";

type RescueCardProps = {
  sizes: readonly string[];
  initialRunId: string | null;
};

export function RescueCard({ sizes, initialRunId }: RescueCardProps) {
  const [runId, setRunId] = useState(initialRunId);
  const [size, setSize] = useState(sizes[0] ?? "");
  return (
    <Card>
      <CardHeader>
        <CardTitle>Rescue report</CardTitle>
        <CardDescription>
          Writes one redacted, pasteable markdown file with doctor, config,
          incidents, proxy and log tails
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <Label className="flex items-center gap-2">
            Size
            <Select
              className="w-auto"
              value={size}
              onChange={(event) => setSize(event.target.value)}
            >
              {sizes.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </Select>
          </Label>
          <StartRunButton
            command={RESCUE_COMMAND}
            params={{ size }}
            stay
            onStarted={setRunId}
            disabled={size === ""}
          >
            Write rescue report
          </StartRunButton>
        </div>
        {runId === null ? (
          <p className="text-sm text-muted-foreground">No rescue report yet.</p>
        ) : (
          <RescueRunResult id={runId} />
        )}
      </CardContent>
    </Card>
  );
}

function RescueRunResult({ id }: { id: string }) {
  const state = useRunStream(id);
  const summary =
    state.ended === null
      ? null
      : parseRescueSummary(state.lines.map((line) => line.text));
  if (summary === null) {
    return (
      <div className="flex flex-col gap-2">
        {state.ended === null ? null : (
          <p className="text-sm text-error-foreground">
            The run printed no report path (exit {state.ended.code}).
          </p>
        )}
        <RunOutputBox lines={state.lines} live={state.ended === null} />
      </div>
    );
  }
  return <RescueSummaryView summary={summary} />;
}

function RescueSummaryView({ summary }: { summary: RescueSummary }) {
  const [report, setReport] = useState<RescueReport | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const fetchReport = async (): Promise<RescueReport | null> => {
    const result = await loadJson<RescueReport>(LATEST_REPORT_URL);
    if (!result.ok) {
      setNotice(result.message);
      return null;
    }
    return result.value;
  };

  const copy = async () => {
    const latest = await fetchReport();
    if (latest !== null) {
      await navigator.clipboard.writeText(latest.text);
      setNotice("Copied.");
    }
  };

  const open = async () => {
    const latest = await fetchReport();
    if (latest !== null) {
      setReport(latest);
      setNotice(null);
    }
  };

  return (
    <div className="flex flex-col gap-3 text-sm">
      <ul className="flex flex-col gap-1 font-mono text-xs">
        {summary.lines.map((line) => (
          <li key={line}>{line}</li>
        ))}
      </ul>
      <code
        aria-label="report path"
        className="block break-all rounded-lg bg-muted/40 p-2 text-xs"
      >
        {summary.path}
      </code>
      <div className="flex flex-wrap items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => void copy()}>
          Copy report
        </Button>
        <Button variant="outline" size="sm" onClick={() => void open()}>
          Open
        </Button>
        {notice === null ? null : (
          <span className="text-muted-foreground">{notice}</span>
        )}
      </div>
      {report === null ? null : (
        <div className="rounded-lg border border-border p-3">
          <MarkdownText>{report.text}</MarkdownText>
        </div>
      )}
    </div>
  );
}

"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useFollowScroll } from "@/components/use-follow-scroll";
import {
  INCIDENT_CAUSES,
  healthSummary,
  incidentCounts,
  incidentFrame,
  latestHealth,
  parseIncident,
  type Incident,
} from "@/lib/incidents";
import { levelTextClass } from "@/lib/level-style";
import { type LogFrame, type LogLevel } from "@/lib/log-line";
import type { LogSource } from "@/lib/log-path";

const MAX_LINES = 5000;

const levelClass: Record<LogLevel, string> = {
  error: levelTextClass("error"),
  warn: levelTextClass("warn"),
  info: "",
  debug: "text-muted-foreground",
};

type LogStream = {
  path: string | null;
  error: string | null;
  lines: LogFrame[];
};

export function LogView() {
  const [source, setSource] = useState<LogSource>("server");

  return (
    <div className="flex flex-col gap-3">
      <Tabs
        value={source}
        onValueChange={(next) => setSource(next as LogSource)}
      >
        <TabsList>
          <TabsTrigger value="server">Ollama server</TabsTrigger>
          <TabsTrigger value="launcher">Launcher</TabsTrigger>
          <TabsTrigger value="incidents">Incidents</TabsTrigger>
        </TabsList>
      </Tabs>
      <LogPanel key={source} source={source} />
    </div>
  );
}

function LogPanel({ source }: { source: LogSource }) {
  const stream = useLogStream(source);
  const [frozenAt, setFrozenAt] = useState<number | null>(null);
  const [filter, setFilter] = useState("");
  const incidents =
    source === "incidents" ? parseIncidents(stream.lines) : null;
  const lines =
    incidents === null ? stream.lines : incidents.map(incidentFrame);

  return (
    <div className="flex flex-col gap-3">
      <StatusPill path={stream.path} error={stream.error} />
      {incidents === null ? null : (
        <IncidentHeader incidents={incidents} lines={stream.lines} />
      )}
      <LogToolbar
        filter={filter}
        onFilter={setFilter}
        paused={frozenAt !== null}
        newCount={frozenAt === null ? 0 : lines.length - frozenAt}
        onTogglePause={() =>
          setFrozenAt(frozenAt === null ? lines.length : null)
        }
      />
      <LogOutput lines={visibleLines(lines, frozenAt, filter)} />
    </div>
  );
}

function parseIncidents(lines: LogFrame[]): Incident[] {
  return lines.flatMap((line) => {
    const incident = parseIncident(line.text);
    return incident === null ? [] : [incident];
  });
}

function IncidentHeader({
  incidents,
  lines,
}: {
  incidents: Incident[];
  lines: LogFrame[];
}) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <IncidentCounts incidents={incidents} />
      <ClassifierHealthPill lines={lines} />
    </div>
  );
}

function ClassifierHealthPill({ lines }: { lines: LogFrame[] }) {
  const health = latestHealth(lines.map((line) => line.text));
  return (
    <Badge
      variant="outline"
      className={`text-xs ${health === null ? "text-muted-foreground" : ""}`}
      aria-label="classifier health"
    >
      {healthSummary(health)}
    </Badge>
  );
}

function IncidentCounts({ incidents }: { incidents: Incident[] }) {
  const counts = incidentCounts(incidents);
  return (
    <div className="flex flex-wrap gap-2" aria-label="incident counts">
      {INCIDENT_CAUSES.map((cause) => (
        <Badge
          key={cause}
          variant="outline"
          className={counts[cause] === 0 ? "text-muted-foreground" : ""}
        >
          {cause} {counts[cause]}
        </Badge>
      ))}
    </div>
  );
}

function visibleLines(
  lines: LogFrame[],
  frozenAt: number | null,
  filter: string,
): LogFrame[] {
  const shown = frozenAt === null ? lines : lines.slice(0, frozenAt);
  return filter === ""
    ? shown
    : shown.filter((line) => line.text.includes(filter));
}

function LogToolbar({
  filter,
  onFilter,
  paused,
  newCount,
  onTogglePause,
}: {
  filter: string;
  onFilter: (filter: string) => void;
  paused: boolean;
  newCount: number;
  onTogglePause: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <input
        type="search"
        placeholder="Filter lines"
        value={filter}
        onChange={(event) => onFilter(event.target.value)}
        className="min-w-0 flex-1 rounded-md border border-border bg-background px-2 py-1 text-sm"
      />
      <Button variant="outline" size="sm" onClick={onTogglePause}>
        {paused ? "Resume" : "Pause"}
      </Button>
      {newCount > 0 ? (
        <span className="text-xs text-muted-foreground">
          {newCount} new lines
        </span>
      ) : null}
    </div>
  );
}

function StatusPill({
  path,
  error,
}: {
  path: string | null;
  error: string | null;
}) {
  if (error !== null) {
    return (
      <Badge
        variant="outline"
        className={`w-fit break-all ${levelTextClass("error")}`}
      >
        {error}
      </Badge>
    );
  }
  if (path === null) {
    return (
      <Badge variant="outline" className="w-fit text-muted-foreground">
        connecting…
      </Badge>
    );
  }
  return (
    <Badge
      variant="outline"
      className="w-fit break-all text-success-foreground"
    >
      following {path}
    </Badge>
  );
}

function LogOutput({ lines }: { lines: LogFrame[] }) {
  const { outputRef, onScroll } = useFollowScroll<HTMLDivElement>(lines);

  return (
    <div
      ref={outputRef}
      onScroll={onScroll}
      className="max-h-[70vh] overflow-auto rounded-lg bg-muted/40 p-3 font-mono text-xs"
    >
      {lines.map((line, index) => (
        <div
          key={index}
          className={`whitespace-pre-wrap break-all ${line.level === null ? "" : levelClass[line.level]}`}
        >
          {line.text}
        </div>
      ))}
    </div>
  );
}

function useLogStream(logSource: LogSource): LogStream {
  const [stream, setStream] = useState<LogStream>({
    path: null,
    error: null,
    lines: [],
  });
  useEffect(() => {
    let active = true;
    let source: EventSource | undefined;
    const start = async () => {
      const response = await fetch(`/api/logs/path?source=${logSource}`, {
        cache: "no-store",
      });
      if (!active) {
        return;
      }
      if (!response.ok) {
        const message = await response.text();
        setStream((previous) => ({ ...previous, error: message }));
        return;
      }
      const { path } = (await response.json()) as { path: string };
      setStream((previous) => ({ ...previous, path }));
      source = new EventSource(`/api/logs/events?source=${logSource}`);
      source.onmessage = (message) => {
        const frame = JSON.parse(message.data) as LogFrame;
        setStream((previous) => ({
          ...previous,
          lines: appendCapped(previous.lines, frame),
        }));
      };
    };
    void start();
    return () => {
      active = false;
      source?.close();
    };
  }, [logSource]);
  return stream;
}

function appendCapped(lines: LogFrame[], frame: LogFrame): LogFrame[] {
  const next = [...lines, frame];
  return next.length > MAX_LINES ? next.slice(next.length - MAX_LINES) : next;
}

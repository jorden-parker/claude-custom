"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Shimmer } from "@/components/ai-elements/shimmer";
import { StreamOutput } from "@/components/stream-output";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
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
import {
  averagePromptBytes,
  latestLedger,
  ledgerTools,
  parseProxyRow,
  prefixHitRate,
  prefixSummary,
  proxyFrame,
  topDivergingSections,
  type ProxyLedger,
  type ProxyRow,
} from "@/lib/proxy-log";
import { type LogFrame, type LogLevel } from "@/lib/log-line";
import type { LogSource } from "@/lib/log-path";

const MAX_LINES = 5000;
const LOG_SOURCES: readonly LogSource[] = [
  "server",
  "launcher",
  "incidents",
  "proxy",
];

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
        <TabsList className="max-w-full justify-start overflow-x-auto">
          <TabsTrigger value="server">Ollama server</TabsTrigger>
          <TabsTrigger value="launcher">Launcher</TabsTrigger>
          <TabsTrigger value="incidents">Incidents</TabsTrigger>
          <TabsTrigger value="proxy">Proxy</TabsTrigger>
        </TabsList>
        {LOG_SOURCES.map((logSource) => (
          <TabsContent
            key={logSource}
            value={logSource}
            className="animate-in fade-in duration-200 motion-reduce:animate-none"
          >
            <LogPanel source={logSource} />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}

function LogPanel({ source }: { source: LogSource }) {
  const stream = useLogStream(source);
  const [frozenAt, setFrozenAt] = useState<number | null>(null);
  const [filter, setFilter] = useState("");
  const incidents =
    source === "incidents" ? parseIncidents(stream.lines) : null;
  const requests = source === "proxy" ? parseRequests(stream.lines) : null;
  const lines = framesOf(stream.lines, incidents, requests);

  return (
    <div className="flex flex-col gap-3">
      <StatusPill path={stream.path} error={stream.error} />
      {incidents === null ? null : (
        <IncidentHeader incidents={incidents} lines={stream.lines} />
      )}
      {requests === null ? null : <ProxyHeader requests={requests} />}
      {requests === null ? null : <ProxyRecordHint />}
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
      {requests === null ? null : <LedgerPanel requests={requests} />}
    </div>
  );
}

function framesOf(
  raw: LogFrame[],
  incidents: Incident[] | null,
  requests: ProxyRow[] | null,
): LogFrame[] {
  if (incidents !== null) {
    return incidents.map(incidentFrame);
  }
  if (requests !== null) {
    return requests.map(proxyFrame);
  }
  return raw;
}

function parseRequests(lines: LogFrame[]): ProxyRow[] {
  return lines.flatMap((line) => {
    const request = parseProxyRow(line.text);
    return request === null ? [] : [request];
  });
}

function ProxyHeader({ requests }: { requests: ProxyRow[] }) {
  const sections = topDivergingSections(requests);
  return (
    <div className="flex flex-wrap items-center gap-2">
      <Badge variant="outline" aria-label="prefix hit rate">
        {prefixSummary(prefixHitRate(requests))}
      </Badge>
      <Badge
        variant="outline"
        className="text-muted-foreground"
        aria-label="average prompt bytes"
      >
        {averagePromptBytes(requests)} bytes per prompt
      </Badge>
      <div className="flex flex-wrap gap-2" aria-label="diverging sections">
        {sections.map((entry) => (
          <Badge key={entry.section} variant="outline">
            {entry.section} {entry.count}
          </Badge>
        ))}
      </div>
    </div>
  );
}

function ProxyRecordHint() {
  return (
    <p className="text-xs text-muted-foreground">
      <Link
        href="/settings#CLAUDE_OLLAMA_PROXY_RECORD"
        className="underline underline-offset-2"
      >
        Record requests for replay
      </Link>{" "}
      on the Settings page to save each body for messages-bench and the cache
      probe.
    </p>
  );
}

function LedgerPanel({ requests }: { requests: ProxyRow[] }) {
  const ledger = latestLedger(requests);
  if (ledger === null) {
    return null;
  }
  return (
    <div
      className="flex flex-col gap-1 rounded-lg border border-border p-3 text-xs"
      aria-label="tool schema ledger"
    >
      <div className="text-muted-foreground">
        latest request: system {ledger.system} · messages {ledger.messages}
      </div>
      <LedgerBars ledger={ledger} />
    </div>
  );
}

function LedgerBars({ ledger }: { ledger: ProxyLedger }) {
  return (
    <>
      {ledgerTools(ledger).map((tool) => (
        <div
          key={tool.name}
          data-tool={tool.name}
          data-bytes={tool.bytes}
          className="grid grid-cols-[minmax(8rem,1fr)_4rem_3fr] items-center gap-2 font-mono"
        >
          <span className="truncate">{tool.name}</span>
          <span className="text-right">{tool.bytes}</span>
          <Progress
            value={Math.round(tool.share * 100)}
            aria-label={tool.name}
          />
        </div>
      ))}
    </>
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
      <Input
        type="search"
        aria-label="Filter lines"
        placeholder="Filter lines"
        value={filter}
        onChange={(event) => onFilter(event.target.value)}
        className="min-w-0 flex-1 sm:max-w-xs"
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
        <Shimmer as="span" className="motion-reduce:hidden">
          connecting…
        </Shimmer>
        <span className="hidden motion-reduce:inline">connecting…</span>
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
  return (
    <StreamOutput
      lines={lines.map((line, index) => ({
        key: index,
        text: line.text,
        className: line.level === null ? "" : levelClass[line.level],
      }))}
    />
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

"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useFollowScroll } from "@/components/use-follow-scroll";
import { type LogFrame, type LogLevel } from "@/lib/log-line";
import type { LogSource } from "@/lib/log-path";

const MAX_LINES = 5000;

const levelClass: Record<LogLevel, string> = {
  error: "text-red-500",
  warn: "text-amber-500",
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

  return (
    <div className="flex flex-col gap-3">
      <StatusPill path={stream.path} error={stream.error} />
      <LogToolbar
        filter={filter}
        onFilter={setFilter}
        paused={frozenAt !== null}
        newCount={frozenAt === null ? 0 : stream.lines.length - frozenAt}
        onTogglePause={() =>
          setFrozenAt(frozenAt === null ? stream.lines.length : null)
        }
      />
      <LogOutput lines={visibleLines(stream.lines, frozenAt, filter)} />
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
      <Badge variant="outline" className="w-fit break-all text-red-500">
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
    <Badge variant="outline" className="w-fit break-all text-emerald-600">
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

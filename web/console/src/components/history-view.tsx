"use client";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import { Select } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { diffLines } from "diff";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import type { HistoryChange, HistoryEntry } from "@/lib/history";
import { ScrollArea } from "@/components/ui/scroll-area";

export function HistoryView() {
  const [entries, setEntries] = useState<HistoryEntry[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<HistoryChange | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [highlightId, setHighlightId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [reloads, setReloads] = useState(0);

  useEffect(() => {
    const loadEntries = async () => {
      const response = await fetch("/api/history", { cache: "no-store" });
      setEntries(
        ((await response.json()) as { entries: HistoryEntry[] }).entries,
      );
    };
    void loadEntries();
  }, [reloads]);

  useEffect(() => {
    if (selectedId === null) {
      return;
    }
    const loadDetail = async () => {
      const response = await fetch(`/api/history/${selectedId}`, {
        cache: "no-store",
      });
      if (response.ok) {
        setDetail((await response.json()) as HistoryChange);
      }
    };
    void loadDetail();
  }, [selectedId]);

  if (entries === null) {
    return <p className="text-sm text-muted-foreground">Loading history...</p>;
  }
  if (entries.length === 0) {
    return <EmptyHistory />;
  }

  const shown =
    detail !== null && detail.entry.id === selectedId ? detail : null;

  const selectEntry = (id: string) => {
    setSelectedId(id);
    setConfirming(false);
    setMessage(null);
  };

  const restore = async (id: string) => {
    setConfirming(false);
    const response = await fetch(`/api/history/${id}/restore`, {
      method: "POST",
    });
    const body = (await response.json()) as {
      entry?: HistoryEntry | null;
      message?: string;
    };
    if (!response.ok) {
      setMessage(body.message ?? "Restore failed");
      return;
    }
    setMessage(null);
    setHighlightId(body.entry?.id ?? null);
    setReloads((count) => count + 1);
  };

  return (
    <section className="grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)]">
      <HistoryList
        entries={entries}
        selectedId={selectedId}
        highlightId={highlightId}
        onSelect={selectEntry}
      />
      <div className="flex flex-col gap-3">
        {shown === null ? (
          <p className="text-sm text-muted-foreground">
            Select a change to see its diff.
          </p>
        ) : (
          <ChangeDetail
            change={shown}
            confirming={confirming}
            message={message}
            onAsk={() => setConfirming(true)}
            onCancel={() => setConfirming(false)}
            onConfirm={() => void restore(shown.entry.id)}
          />
        )}
      </div>
    </section>
  );
}

function HistoryList({
  entries,
  selectedId,
  highlightId,
  onSelect,
}: {
  entries: HistoryEntry[];
  selectedId: string | null;
  highlightId: string | null;
  onSelect: (id: string) => void;
}) {
  const [kind, setKind] = useState("all");
  const kinds = [...new Set(entries.map((entry) => entry.kind))];
  const visible =
    kind === "all" ? entries : entries.filter((entry) => entry.kind === kind);
  return (
    <div className="flex flex-col gap-3">
      <Label className="flex items-center gap-2">
        Kind
        <Select
          value={kind}
          onChange={(event) => setKind(event.target.value)}
          className="w-auto"
        >
          <option value="all">All kinds</option>
          {kinds.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </Select>
      </Label>
      <ul className="flex flex-col gap-1">
        {visible.map((entry) => (
          <li key={entry.id}>
            <Button
              type="button"
              variant="ghost"
              onClick={() => onSelect(entry.id)}
              aria-pressed={entry.id === selectedId}
              data-selected={entry.id === selectedId}
              className="h-auto w-full flex-col items-start justify-start gap-1 whitespace-normal border px-3 py-2 text-left text-sm data-[selected=true]:bg-muted"
            >
              <span className="flex flex-wrap gap-2 text-xs">
                <span className="rounded border px-1">{entry.kind}</span>
                <span className="text-muted-foreground">{entry.source}</span>
                <span>{formatTime(entry.at)}</span>
                {entry.id === highlightId ? (
                  <span className="font-medium text-success-foreground">
                    new
                  </span>
                ) : null}
              </span>
              <span className="break-all font-mono text-xs">{entry.path}</span>
            </Button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function ChangeDetail({
  change,
  confirming,
  message,
  onAsk,
  onCancel,
  onConfirm,
}: {
  change: HistoryChange;
  confirming: boolean;
  message: string | null;
  onAsk: () => void;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const { entry, before, after } = change;
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-1 text-sm">
        <p className="font-mono break-all">{entry.path}</p>
        <p className="text-muted-foreground">
          {entry.kind} · {entry.source} · {formatTime(entry.at)}
        </p>
      </div>
      <DiffView before={before} after={after} />
      {confirming ? (
        <RestoreConfirm
          kind={entry.kind}
          path={entry.path}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      ) : (
        <div>
          <Button
            variant="outline"
            onClick={onAsk}
            disabled={before === null}
            title={
              before === null
                ? "This change created the file, so there is no earlier version"
                : undefined
            }
          >
            Restore this version
          </Button>
        </div>
      )}
      {message === null ? null : (
        <p className="text-sm text-error-foreground">{message}</p>
      )}
    </div>
  );
}

function RestoreConfirm({
  kind,
  path,
  onConfirm,
  onCancel,
}: {
  kind: string;
  path: string;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <AlertDialog
      open
      onOpenChange={(open) => {
        if (!open) {
          onCancel();
        }
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Restore Settings</AlertDialogTitle>
          <AlertDialogDescription>
            {path} returns to the version before this change.
            {kind === "launch-agent"
              ? " Then use Apply on the Server page to reload Ollama."
              : null}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={onConfirm}>
            Restore Settings
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function DiffView({ before, after }: { before: string | null; after: string }) {
  const lines = diffLines(before ?? "", after).flatMap((part) =>
    part.value
      .replace(/\n$/, "")
      .split("\n")
      .map((text) => ({ text, className: diffClass(part) })),
  );
  return (
    <ScrollArea className="rounded-md border" viewportClassName="max-h-96">
      <pre className="max-w-full p-3 font-mono text-xs">
        {lines.map((line, index) => (
          <span
            key={index}
            className={`block whitespace-pre ${line.className}`}
          >
            {line.text || " "}
          </span>
        ))}
      </pre>
    </ScrollArea>
  );
}

function diffClass(part: { added?: boolean; removed?: boolean }): string {
  if (part.added) {
    return "bg-success text-success-foreground";
  }
  if (part.removed) {
    return "bg-error text-error-foreground";
  }
  return "text-muted-foreground";
}

function EmptyHistory() {
  return (
    <Empty className="border">
      <EmptyHeader>
        <EmptyTitle>No changes recorded yet.</EmptyTitle>
        <EmptyDescription>
          Changes made by claude-tools, ollama-agent and the console show up
          here. Recording is on by default; set CLAUDE_CUSTOM_HISTORY=off in the
          environment to turn it off.
        </EmptyDescription>
      </EmptyHeader>
    </Empty>
  );
}

function formatTime(at: string): string {
  return new Date(at).toLocaleString();
}

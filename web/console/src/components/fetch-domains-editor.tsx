"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { SUGGESTED_HOSTS, isValidHost, normalizeHost } from "@/lib/fetch-domain-rules";

type FetchDomainState = {
  path: string;
  hosts: string[];
  ignored: string[];
  suggested: string[];
};

type Row = {
  host: string;
  on: boolean;
  suggestedOnly: boolean;
};

type HistoryEntry = {
  id: string;
  at: string;
  kind: string;
  source: string;
};

const SAVED_MESSAGE = "saved; applies to the next claude-ollama launch";
const INVALID_MESSAGE = "not a hostname (expected something like docs.python.org)";
const FETCH_DOMAIN_KIND = "fetch-domains";

export function FetchDomainsEditor() {
  const [saved, setSaved] = useState<FetchDomainState | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [draft, setDraft] = useState("");
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const scrollTarget = useRef<string | null>(null);

  const applyState = useCallback((state: FetchDomainState) => {
    setSaved(state);
    setRows(rowsFrom(state));
    setError(null);
  }, []);

  useEffect(() => {
    const loadState = async () => {
      const response = await fetch("/api/fetch-domains", { cache: "no-store" });
      if (!response.ok) {
        setError(await responseMessage(response));
        return;
      }
      applyState((await response.json()) as FetchDomainState);
    };
    void loadState();
    void fetchHistory().then(setHistory);
  }, [applyState]);

  useEffect(() => {
    const host = scrollTarget.current;
    if (host === null) {
      return;
    }
    scrollTarget.current = null;
    document.querySelector<HTMLElement>(`[data-host="${host}"]`)?.scrollIntoView?.({ block: "center" });
  }, [rows]);

  const draftError = draft.trim() !== "" && !isValidHost(normalizeHost(draft)) ? INVALID_MESSAGE : null;
  const onHosts = rows.filter((row) => row.on).map((row) => row.host);
  const dirty = saved !== null && JSON.stringify(onHosts) !== JSON.stringify(saved.hosts);

  function toggle(host: string) {
    setRows((current) => current.map((row) => (row.host === host ? { ...row, on: !row.on } : row)));
    setMessage(null);
  }

  function discard() {
    if (saved !== null) {
      setRows(rowsFrom(saved));
    }
  }

  function remove(host: string) {
    setRows((current) => current.filter((row) => row.host !== host));
  }

  function addDraft() {
    const host = normalizeHost(draft);
    if (!isValidHost(host)) {
      return;
    }
    setRows((current) =>
      current.some((row) => row.host === host) ? turnOn(current, host) : insertCustom(current, host),
    );
    setDraft("");
    setMessage(null);
    scrollTarget.current = host;
  }

  async function save() {
    setSaving(true);
    const response = await fetch("/api/fetch-domains", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ hosts: onHosts }),
    });
    setSaving(false);
    if (!response.ok) {
      setError(await responseMessage(response));
      return;
    }
    applyState((await response.json()) as FetchDomainState);
    setMessage(SAVED_MESSAGE);
    void fetchHistory().then(setHistory);
  }

  return (
    <div className="flex flex-col gap-6 pb-24">
      <p className="rounded-md border border-amber-500/60 bg-amber-500/10 px-4 py-3 text-sm">
        Each host listed here can be read by the local model&apos;s sessions.
      </p>
      {saved ? <p className="text-sm text-muted-foreground">File: {saved.path}</p> : null}
      {error ? <p className="text-sm text-red-600">{error}</p> : null}
      {saved && saved.ignored.length > 0 ? (
        <div className="rounded-md border border-amber-500/60 bg-amber-500/10 px-4 py-3 text-sm">
          <p className="font-medium">Ignored lines in the file</p>
          <ul className="mt-2 flex flex-col gap-1">
            {saved.ignored.map((line, index) => (
              <li key={`${line}-${index}`}>
                <code>{line}</code>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <form
        className="flex items-start gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          addDraft();
        }}
      >
        <div className="flex flex-col gap-1">
          <input
            aria-label="Add host"
            aria-invalid={draftError !== null}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            placeholder="docs.example.com"
            className={`rounded-md border bg-background px-3 py-2 text-sm ${draftError ? "border-red-500 ring-2 ring-red-500" : "border-input"}`}
          />
          {draftError ? <span className="text-xs text-red-600">{draftError}</span> : null}
        </div>
        <Button type="submit" variant="outline" disabled={draft.trim() === "" || draftError !== null}>
          Add
        </Button>
      </form>

      <ul className="flex flex-col divide-y rounded-md border">
        {rows.map((row) => (
          <li
            key={row.host}
            data-host={row.host}
            className="animate-in fade-in slide-in-from-top-1 flex items-center justify-between gap-4 px-4 py-3"
          >
            <label className="flex items-center gap-3 text-sm">
              <input
                type="checkbox"
                role="switch"
                aria-label={row.host}
                checked={row.on}
                onChange={() => toggle(row.host)}
                className="size-4"
              />
              <span className="font-mono">{row.host}</span>
              {row.suggestedOnly && !row.on ? (
                <span className="rounded bg-muted px-2 py-0.5 text-xs text-muted-foreground">suggested</span>
              ) : null}
            </label>
            {isCustom(row.host) ? (
              <Button type="button" variant="ghost" size="sm" onClick={() => remove(row.host)}>
                Remove
              </Button>
            ) : null}
          </li>
        ))}
      </ul>

      <section className="flex flex-col gap-2">
        <h2 className="text-lg font-medium">History</h2>
        {history.length === 0 ? (
          <p className="text-sm text-muted-foreground">No saves yet.</p>
        ) : (
          <ul className="flex flex-col gap-1 text-sm">
            {history.map((entry) => (
              <li key={entry.id}>{new Date(entry.at).toLocaleString()}</li>
            ))}
          </ul>
        )}
      </section>

      {dirty ? (
        <div className="sticky bottom-0 flex items-center justify-between gap-4 border-t bg-background px-4 py-3">
          <span className="text-sm">Unsaved changes</span>
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={discard}>
              Discard
            </Button>
            <Button type="button" onClick={() => void save()} disabled={saving}>
              Save
            </Button>
          </div>
        </div>
      ) : null}
      {message ? <p className="text-sm text-green-700">{message}</p> : null}
    </div>
  );
}

function rowsFrom(state: FetchDomainState): Row[] {
  const listed = state.hosts.map((host) => ({ host, on: true, suggestedOnly: false }));
  const offered = state.suggested
    .filter((host) => !state.hosts.includes(host))
    .map((host) => ({ host, on: false, suggestedOnly: true }));
  return [...listed, ...offered];
}

function turnOn(rows: Row[], host: string): Row[] {
  return rows.map((row) => (row.host === host ? { ...row, on: true } : row));
}

function insertCustom(rows: Row[], host: string): Row[] {
  const custom: Row = { host, on: true, suggestedOnly: false };
  const firstOffered = rows.findIndex((row) => row.suggestedOnly);
  if (firstOffered === -1) {
    return [...rows, custom];
  }
  return [...rows.slice(0, firstOffered), custom, ...rows.slice(firstOffered)];
}

function isCustom(host: string): boolean {
  return !SUGGESTED_HOSTS.includes(host);
}

async function fetchHistory(): Promise<HistoryEntry[]> {
  const response = await fetch("/api/history", { cache: "no-store" });
  if (!response.ok) {
    return [];
  }
  const body = (await response.json()) as { entries: HistoryEntry[] };
  return body.entries.filter((entry) => entry.kind === FETCH_DOMAIN_KIND);
}

async function responseMessage(response: Response): Promise<string> {
  try {
    return ((await response.json()) as { message: string }).message;
  } catch {
    return `request failed (${response.status})`;
  }
}

"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import type { InvalidLine, PolicyFile } from "@/lib/machine-policy-rules";

type PolicyFileState = {
  path: string;
  text: string | null;
  valid: string[];
  invalid: InvalidLine[];
};

type FetchDomainsState = { path: string; count: number; editor: string };
type SandboxOffState = { exists: boolean; path: string };

type MachineState = {
  dir: string;
  files: Record<PolicyFile, PolicyFileState> & {
    "fetch-domains": FetchDomainsState;
  };
  sandboxOff: SandboxOffState;
  knownTools: string[];
};

type HistoryEntry = {
  id: string;
  at: string;
  kind: string;
  source: string;
};

const EDITABLE_FILES: readonly PolicyFile[] = [
  "gh-repos",
  "command-rules",
  "enabled-tools",
];
const HISTORY_KIND_PREFIX = "machine-";
const SAVED_MESSAGE = "saved; applies to the next claude-ollama launch";
const RESTORED_MESSAGE = "restored; applies to the next claude-ollama launch";
const DESCRIPTIONS: Record<PolicyFile, string> = {
  "gh-repos":
    "Repositories beyond the project's origin that sessions may use with gh, one owner/name or owner/* per line.",
  "command-rules":
    "Rules for gh and short writes: allow or deny, program, action and an optional scope. A # line is a comment.",
  "enabled-tools":
    "Bare tool names taken off the overlay's deny list, one per line.",
};

type Loaded =
  | { ok: true; machine: MachineState; history: HistoryEntry[] }
  | { ok: false; message: string };

export function MachinePolicyEditor() {
  const [state, setState] = useState<MachineState | null>(null);
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const apply = useCallback((loaded: Loaded) => {
    if (!loaded.ok) {
      setError(loaded.message);
      return;
    }
    setState(loaded.machine);
    setHistory(loaded.history);
    setError(null);
  }, []);

  useEffect(() => {
    void loadPolicy().then(apply);
  }, [apply]);

  async function save(file: PolicyFile, text: string) {
    const response = await fetch("/api/machine", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ file, lines: text.split("\n") }),
    });
    if (!response.ok) {
      setMessage(null);
      setError(await failureMessage(response));
      return;
    }
    setMessage(SAVED_MESSAGE);
    apply(await loadPolicy());
  }

  async function restore(id: string) {
    const response = await fetch(`/api/history/${id}/restore`, {
      method: "POST",
    });
    if (!response.ok) {
      setMessage(null);
      setError(await failureMessage(response));
      return;
    }
    setMessage(RESTORED_MESSAGE);
    apply(await loadPolicy());
  }

  if (state === null) {
    return (
      <p className="text-sm text-muted-foreground">
        {error ?? "Loading the machine policy..."}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <p className="text-sm text-muted-foreground">Folder: {state.dir}</p>
      {error ? <p className="text-sm text-red-600">{error}</p> : null}
      {message ? <p className="text-sm text-green-700">{message}</p> : null}
      {EDITABLE_FILES.map((file) => (
        <PolicyCard
          key={`${file}:${state.files[file].text ?? ""}`}
          file={file}
          saved={state.files[file]}
          entries={historyOf(history, file)}
          onSave={save}
          onRestore={restore}
        />
      ))}
      <FetchDomainsCard state={state.files["fetch-domains"]} />
      <SandboxOffCard state={state.sandboxOff} />
    </div>
  );
}

function PolicyCard({
  file,
  saved,
  entries,
  onSave,
  onRestore,
}: {
  file: PolicyFile;
  saved: PolicyFileState;
  entries: HistoryEntry[];
  onSave: (file: PolicyFile, text: string) => Promise<void>;
  onRestore: (id: string) => Promise<void>;
}) {
  const [draft, setDraft] = useState(saved.text ?? "");
  return (
    <section
      aria-label={file}
      className="flex flex-col gap-3 rounded-md border p-4"
    >
      <h2 className="font-mono text-lg font-medium">{file}</h2>
      <p className="text-sm text-muted-foreground">{DESCRIPTIONS[file]}</p>
      <p className="text-xs text-muted-foreground">File: {saved.path}</p>
      <textarea
        aria-label={`Lines for ${file}`}
        value={draft}
        onChange={(event) => setDraft(event.target.value)}
        rows={6}
        className="rounded-md border bg-background p-2 font-mono text-sm"
      />
      <InvalidLines invalid={saved.invalid} />
      <div>
        <Button type="button" onClick={() => void onSave(file, draft)}>
          Save
        </Button>
      </div>
      <HistoryList entries={entries} onRestore={onRestore} />
    </section>
  );
}

function InvalidLines({ invalid }: { invalid: InvalidLine[] }) {
  if (invalid.length === 0) {
    return null;
  }
  return (
    <div className="rounded-md border border-amber-500/60 bg-amber-500/10 px-4 py-3 text-sm">
      <p className="font-medium">The launcher ignores these lines</p>
      <ul className="mt-2 flex flex-col gap-1">
        {invalid.map((entry, index) => (
          <li key={`${entry.line}-${index}`}>
            <code>{entry.line}</code>{" "}
            <span className="text-muted-foreground">{entry.reason}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function HistoryList({
  entries,
  onRestore,
}: {
  entries: HistoryEntry[];
  onRestore: (id: string) => Promise<void>;
}) {
  if (entries.length === 0) {
    return <p className="text-sm text-muted-foreground">No saves yet.</p>;
  }
  return (
    <ul className="flex flex-col gap-1 text-sm">
      {entries.map((entry) => (
        <li key={entry.id} className="flex items-center justify-between gap-4">
          <span>{new Date(entry.at).toLocaleString()}</span>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => void onRestore(entry.id)}
          >
            Restore before this save
          </Button>
        </li>
      ))}
    </ul>
  );
}

function FetchDomainsCard({ state }: { state: FetchDomainsState }) {
  const noun = state.count === 1 ? "host" : "hosts";
  return (
    <section
      aria-label="fetch-domains"
      className="flex flex-col gap-3 rounded-md border p-4"
    >
      <h2 className="font-mono text-lg font-medium">fetch-domains</h2>
      <p className="text-sm">
        {state.count} {noun} listed. Edited on its own page.
      </p>
      <p className="text-xs text-muted-foreground">File: {state.path}</p>
      <Link href={state.editor} className="text-sm underline">
        Edit fetch domains
      </Link>
    </section>
  );
}

function SandboxOffCard({ state }: { state: SandboxOffState }) {
  const commands = `touch ${state.path}\nrm ${state.path}`;
  return (
    <section
      aria-label="sandbox-off"
      className="flex flex-col gap-3 rounded-md border p-4"
    >
      <h2 className="font-mono text-lg font-medium">sandbox-off</h2>
      <p className="text-sm">
        State:{" "}
        <span className="font-medium">{state.exists ? "on" : "off"}</span>
      </p>
      <p className="text-sm text-muted-foreground">
        {state.exists
          ? "The personal Claude sandbox is off on this machine."
          : "The personal Claude sandbox is on."}
      </p>
      <p className="text-xs text-muted-foreground">File: {state.path}</p>
      <p className="text-sm text-muted-foreground">
        Turn it off with touch, back on with rm. The console does not create or
        delete this file.
      </p>
      <pre className="overflow-x-auto rounded-md bg-muted p-3 text-sm">
        {commands}
      </pre>
    </section>
  );
}

function historyOf(entries: HistoryEntry[], file: PolicyFile): HistoryEntry[] {
  return entries.filter(
    (entry) => entry.kind === `${HISTORY_KIND_PREFIX}${file}`,
  );
}

async function loadPolicy(): Promise<Loaded> {
  const response = await fetch("/api/machine", { cache: "no-store" });
  if (!response.ok) {
    return { ok: false, message: await failureMessage(response) };
  }
  return {
    ok: true,
    machine: (await response.json()) as MachineState,
    history: await fetchHistory(),
  };
}

async function fetchHistory(): Promise<HistoryEntry[]> {
  const response = await fetch("/api/history", { cache: "no-store" });
  if (!response.ok) {
    return [];
  }
  return ((await response.json()) as { entries: HistoryEntry[] }).entries;
}

async function failureMessage(response: Response): Promise<string> {
  const body = (await response.json().catch(() => null)) as {
    message?: string;
  } | null;
  return body?.message ?? `request failed (${response.status})`;
}

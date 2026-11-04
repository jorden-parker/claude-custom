"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { PruneConfirm } from "@/components/prune-confirm";
import { StartRunButton } from "@/components/start-run-button";
import { postRun } from "@/lib/post-run";
import {
  gigabytes,
  sizeStateOf,
  type SizeState,
  type SizeStatus,
  type WeightFile,
} from "@/lib/model-display";
import type { ModelAction, ServerModel, ServerModelStatus } from "@/lib/model-server";
import type { EmbeddingStatus, ModelsSnapshot } from "@/lib/models";
import type { RunSummary } from "@/lib/run-log";

const POLL_MS = 5000;
const FLASH_MS = 2000;

const STATE_STYLE: Record<SizeState, string> = {
  installed: "bg-success text-success-foreground",
  missing: "bg-muted text-muted-foreground",
  partial: "bg-warning text-warning-foreground",
  mismatch: "bg-error text-error-foreground",
};

const STATUS_STYLE: Record<ServerModelStatus, string> = {
  loaded: "bg-success text-success-foreground",
  loading: "bg-warning text-warning-foreground",
  unloaded: "bg-muted text-muted-foreground",
};

type Polled = { snapshot: ModelsSnapshot | null; pruneRunning: boolean };

export function ModelsView() {
  const { polled, refresh } = usePolledModels();
  const { snapshot, pruneRunning } = polled;
  const flashing = useFlashingSizes(snapshot?.sizes);

  return (
    <div className="flex flex-col gap-8">
      {snapshot?.server === "down" ? <ServerDownBanner url={snapshot.serverUrl} /> : null}
      <SizesSection sizes={snapshot?.sizes ?? []} flashing={flashing} />
      <EmbeddingSection embedding={snapshot?.embedding} />
      <PresetsSection presets={snapshot?.presets ?? []} onChanged={refresh} />
      <FilesSection snapshot={snapshot} pruneRunning={pruneRunning} />
    </div>
  );
}

function ServerDownBanner({ url }: { url: string }) {
  return (
    <p className="rounded-md border border-error-border p-3 text-sm text-error-foreground">
      The model server at {url} is not running. Start it, then this page refreshes on its own.
    </p>
  );
}

function SizesSection({ sizes, flashing }: { sizes: SizeStatus[]; flashing: Set<string> }) {
  return (
    <Section title="Sizes">
      <ModelTable headers={["Size", "Preset", "Weights file", "File", "Action"]}>
        {sizes.map((size) => (
          <SizeRow key={size.size} size={size} flashing={flashing.has(size.size)} />
        ))}
      </ModelTable>
    </Section>
  );
}

function EmbeddingSection({ embedding }: { embedding: EmbeddingStatus | undefined }) {
  if (embedding === undefined) {
    return null;
  }
  const installed = embedding.state === "pinned";
  return (
    <Section title="Embedding model">
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span className="font-mono text-xs">{embedding.model ?? "unknown"}</span>
        <span className="font-mono text-xs text-muted-foreground">{embedding.file ?? ""}</span>
        <Badge className={installed ? STATE_STYLE.installed : STATE_STYLE.missing}>
          {installed ? "installed" : "missing"}
        </Badge>
        {installed || embedding.model === null ? null : (
          <StartRunButton command="prepare-embedding" params={{}}>
            Set up
          </StartRunButton>
        )}
      </div>
    </Section>
  );
}

function PresetsSection({ presets, onChanged }: { presets: ServerModel[]; onChanged: () => void }) {
  const [message, setMessage] = useState<string | null>(null);

  const change = async (action: ModelAction, id: string) => {
    setMessage(null);
    const failure = await postModelAction(action, id);
    if (failure !== null) {
      setMessage(failure);
    }
    onChanged();
  };

  return (
    <Section title="On the server">
      <ModelTable headers={["Preset", "Status", "Memory", "Action"]}>
        {presets.map((preset) => (
          <PresetRow key={preset.id} preset={preset} onChange={change} />
        ))}
      </ModelTable>
      {message === null ? null : <p className="text-sm text-error-foreground">{message}</p>}
    </Section>
  );
}

function PresetRow({
  preset,
  onChange,
}: {
  preset: ServerModel;
  onChange: (action: ModelAction, id: string) => void;
}) {
  return (
    <TableRow className="animate-in fade-in">
      <TableCell className="py-2 font-mono text-xs">{preset.id}</TableCell>
      <TableCell>
        <Badge className={STATUS_STYLE[preset.status]}>{preset.status}</Badge>
      </TableCell>
      <TableCell>{preset.bytes === null ? "" : `${gigabytes(preset.bytes)} GB`}</TableCell>
      <TableCell>
        <PresetAction preset={preset} onChange={onChange} />
      </TableCell>
    </TableRow>
  );
}

function PresetAction({
  preset,
  onChange,
}: {
  preset: ServerModel;
  onChange: (action: ModelAction, id: string) => void;
}) {
  if (preset.status === "loading") {
    return null;
  }
  const action: ModelAction = preset.status === "loaded" ? "unload" : "load";
  return (
    <Button variant="outline" size="sm" onClick={() => onChange(action, preset.id)}>
      {action === "load" ? "Load" : "Unload"}
    </Button>
  );
}

function FilesSection({ snapshot, pruneRunning }: { snapshot: ModelsSnapshot | null; pruneRunning: boolean }) {
  const files = snapshot?.files ?? [];
  const prunable = files.filter((file) => snapshot?.prunable.includes(file.name));
  return (
    <Section title="Weight files">
      <ModelTable headers={["File", "State", "Size", "On disk"]}>
        {files.map((file) => (
          <FileRow key={file.name} file={file} />
        ))}
      </ModelTable>
      {prunable.length === 0 ? null : <PruneSection files={prunable} disabled={pruneRunning} />}
    </Section>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-lg font-medium">{title}</h2>
      {children}
    </section>
  );
}

function ModelTable({ headers, children }: { headers: string[]; children: ReactNode }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          {headers.map((header) => (
            <TableHead key={header}>{header}</TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>{children}</TableBody>
    </Table>
  );
}

function PruneSection({ files, disabled }: { files: WeightFile[]; disabled: boolean }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const count = files.length;

  const removeNames = async (names: string[]) => {
    const result = await postRun("prune", { names: names.join(",") });
    if (result.ok) {
      router.push(`/runs/${encodeURIComponent(result.id)}`);
      return;
    }
    setConfirming(false);
    setMessage(result.message);
  };

  return (
    <div className="flex flex-col gap-3">
      <Button variant="outline" className="self-start" disabled={disabled} onClick={() => setConfirming(true)}>
        Remove {count} unused {count === 1 ? "file" : "files"}
      </Button>
      {confirming ? (
        <PruneConfirm files={files} onConfirm={removeNames} onCancel={() => setConfirming(false)} />
      ) : null}
      {message === null ? null : <p className="text-sm text-error-foreground">{message}</p>}
    </div>
  );
}

function SizeRow({ size, flashing }: { size: SizeStatus; flashing: boolean }) {
  const state = sizeStateOf(size);
  const flash = flashing ? "bg-success" : "";
  return (
    <TableRow className={`animate-in fade-in transition-colors duration-1000 ${flash}`}>
      <TableCell className="py-2 font-medium">{size.size}</TableCell>
      <TableCell className="font-mono text-xs">{size.model ?? "unknown"}</TableCell>
      <TableCell className="font-mono text-xs">{size.file ?? "unknown"}</TableCell>
      <TableCell>
        <Badge className={STATE_STYLE[state]}>{state}</Badge>
      </TableCell>
      <TableCell>
        <SizeAction size={size} state={state} />
      </TableCell>
    </TableRow>
  );
}

function SizeAction({ size, state }: { size: SizeStatus; state: SizeState }) {
  if (state === "mismatch") {
    return <span className="text-xs">Run claude-ollama doctor</span>;
  }
  if (state === "installed" || size.file === null) {
    return null;
  }
  return (
    <StartRunButton command="prepare" params={{ size: size.size }}>
      Prepare
    </StartRunButton>
  );
}

function FileRow({ file }: { file: WeightFile }) {
  return (
    <TableRow className="animate-in fade-in">
      <TableCell className="py-2 font-mono text-xs">{file.name}</TableCell>
      <TableCell>
        <Badge variant="outline">{file.state}</Badge>
      </TableCell>
      <TableCell>{file.size ?? ""}</TableCell>
      <TableCell>{gigabytes(file.bytes)} GB</TableCell>
    </TableRow>
  );
}

async function postModelAction(action: ModelAction, id: string): Promise<string | null> {
  try {
    const response = await fetch(`/api/models/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model: id }),
    });
    if (response.ok) {
      return null;
    }
    const body = (await response.json().catch(() => null)) as { message?: string } | null;
    return body?.message ?? `${action} failed with status ${response.status}`;
  } catch {
    return `${action} failed: the console did not answer`;
  }
}

function usePolledModels(): { polled: Polled; refresh: () => void } {
  const [polled, setPolled] = useState<Polled>({ snapshot: null, pruneRunning: false });
  const [refreshCount, setRefreshCount] = useState(0);
  const refresh = useCallback(() => setRefreshCount((count) => count + 1), []);

  useEffect(() => {
    let active = true;
    const load = async () => {
      const [snapshot, runs] = await Promise.all([
        getJson<ModelsSnapshot>("/api/models"),
        getJson<RunSummary[]>("/api/runs"),
      ]);
      if (!active) {
        return;
      }
      setPolled((previous) => ({
        snapshot: snapshot ?? previous.snapshot,
        pruneRunning:
          runs === null
            ? previous.pruneRunning
            : runs.some((run) => run.command === "prune" && run.status === "running"),
      }));
    };
    void load();
    const timer = setInterval(load, POLL_MS);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [refreshCount]);

  return { polled, refresh };
}

function useFlashingSizes(sizes: SizeStatus[] | undefined): Set<string> {
  const previous = useRef<Map<string, SizeState> | null>(null);
  const [flashing, setFlashing] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (sizes === undefined) {
      return;
    }
    const current = new Map(sizes.map((size) => [size.size, sizeStateOf(size)]));
    const before = previous.current;
    previous.current = current;
    if (before === null) {
      return;
    }
    const changed = sizes.filter((size) => before.has(size.size) && before.get(size.size) !== current.get(size.size));
    if (changed.length === 0) {
      return;
    }
    setFlashing(new Set(changed.map((size) => size.size)));
    const timer = setTimeout(() => setFlashing(new Set()), FLASH_MS);
    return () => clearTimeout(timer);
  }, [sizes]);

  return flashing;
}

async function getJson<T>(url: string): Promise<T | null> {
  try {
    const response = await fetch(url, { cache: "no-store" });
    return response.ok ? ((await response.json()) as T) : null;
  } catch {
    return null;
  }
}

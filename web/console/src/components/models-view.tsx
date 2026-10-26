"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { PruneConfirm } from "@/components/prune-confirm";
import { StartRunButton } from "@/components/start-run-button";
import { postRun } from "@/lib/post-run";
import { gigabytes, sizeStateOf, type InstalledModel, type SizeState, type SizeStatus } from "@/lib/model-display";
import type { EmbeddingStatus, ModelsSnapshot } from "@/lib/models";
import type { RunSummary } from "@/lib/run-log";

const POLL_MS = 5000;
const FLASH_MS = 2000;

const STATE_STYLE: Record<SizeState, string> = {
  installed: "bg-green-500/15 text-green-700 dark:text-green-400",
  missing: "bg-muted text-muted-foreground",
  mismatch: "bg-red-500/15 text-red-700 dark:text-red-400",
};

type Polled = { snapshot: ModelsSnapshot | null; pruneRunning: boolean };

export function ModelsView() {
  const { snapshot, pruneRunning } = usePolledModels();
  const flashing = useFlashingSizes(snapshot?.sizes);

  return (
    <div className="flex flex-col gap-8">
      {snapshot?.ollama === "down" ? <OllamaDownBanner /> : null}
      <SizesSection sizes={snapshot?.sizes ?? []} flashing={flashing} />
      <EmbeddingSection embedding={snapshot?.embedding} />
      <InstalledSection snapshot={snapshot} pruneRunning={pruneRunning} />
    </div>
  );
}

function OllamaDownBanner() {
  return (
    <p className="rounded-md border border-red-500/40 p-3 text-sm text-red-700 dark:text-red-400">
      Ollama is not running. Start it, then this page refreshes on its own.
    </p>
  );
}

function SizesSection({ sizes, flashing }: { sizes: SizeStatus[]; flashing: Set<string> }) {
  return (
    <Section title="Sizes">
      <Table headers={["Size", "Model", "Base", "Status", "Action"]}>
        {sizes.map((size) => (
          <SizeRow key={size.size} size={size} flashing={flashing.has(size.size)} />
        ))}
      </Table>
    </Section>
  );
}

function EmbeddingSection({ embedding }: { embedding: EmbeddingStatus | undefined }) {
  if (embedding === undefined) {
    return null;
  }
  const style = embedding.installed ? STATE_STYLE.installed : STATE_STYLE.missing;
  return (
    <Section title="Embedding model">
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span className="font-mono text-xs">{embedding.name ?? "unknown"}</span>
        <Badge className={style}>{embedding.installed ? "installed" : "missing"}</Badge>
        {embedding.installed || embedding.name === null ? null : (
          <StartRunButton command="prepare-embedding" params={{}}>
            Set up
          </StartRunButton>
        )}
      </div>
    </Section>
  );
}

function InstalledSection({ snapshot, pruneRunning }: { snapshot: ModelsSnapshot | null; pruneRunning: boolean }) {
  const prunable = snapshot?.models.filter((model) => snapshot.prunable.includes(model.name)) ?? [];
  return (
    <Section title="Installed models">
      <Table headers={["Name", "Class", "Size", "Loaded"]}>
        {(snapshot?.models ?? []).map((model) => (
          <ModelRow key={model.name} model={model} />
        ))}
      </Table>
      {prunable.length === 0 ? null : <PruneSection models={prunable} disabled={pruneRunning} />}
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

function Table({ headers, children }: { headers: string[]; children: ReactNode }) {
  return (
    <table className="w-full text-left text-sm">
      <thead className="text-muted-foreground">
        <tr>
          {headers.map((header) => (
            <th key={header} className="py-1">
              {header}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>{children}</tbody>
    </table>
  );
}

function PruneSection({ models, disabled }: { models: InstalledModel[]; disabled: boolean }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const count = models.length;

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
        Remove {count} unused {count === 1 ? "model" : "models"}
      </Button>
      {confirming ? (
        <PruneConfirm models={models} onConfirm={removeNames} onCancel={() => setConfirming(false)} />
      ) : null}
      {message === null ? null : <p className="text-sm text-red-700 dark:text-red-400">{message}</p>}
    </div>
  );
}

function SizeRow({ size, flashing }: { size: SizeStatus; flashing: boolean }) {
  const state = sizeStateOf(size);
  const flash = flashing ? "bg-green-500/10" : "";
  return (
    <tr className={`animate-in fade-in transition-colors duration-1000 ${flash}`}>
      <td className="py-2 font-medium">{size.size}</td>
      <td className="font-mono text-xs">{size.model ?? "unknown"}</td>
      <td className="font-mono text-xs">{size.base ?? "unknown"}</td>
      <td>
        <Badge className={STATE_STYLE[state]}>{state}</Badge>
      </td>
      <td>
        <SizeAction size={size} state={state} />
      </td>
    </tr>
  );
}

function SizeAction({ size, state }: { size: SizeStatus; state: SizeState }) {
  if (state === "mismatch") {
    return <span className="text-xs">Run claude-ollama doctor</span>;
  }
  if (state === "missing" && size.model !== null) {
    return (
      <StartRunButton command="prepare" params={{ size: size.size }}>
        Prepare
      </StartRunButton>
    );
  }
  return null;
}

function ModelRow({ model }: { model: InstalledModel }) {
  return (
    <tr className="animate-in fade-in">
      <td className="py-2 font-mono text-xs">{model.name}</td>
      <td>
        <Badge variant="outline">{model.class}</Badge>
      </td>
      <td>{gigabytes(model.bytes)} GB</td>
      <td>
        {model.loaded ? <span aria-label="loaded" className="inline-block size-2 animate-pulse rounded-full bg-green-500" /> : null}
      </td>
    </tr>
  );
}

function usePolledModels(): Polled {
  const [polled, setPolled] = useState<Polled>({ snapshot: null, pruneRunning: false });

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
        pruneRunning: runs === null ? previous.pruneRunning : runs.some((run) => run.command === "prune" && run.status === "running"),
      }));
    };
    void load();
    const timer = setInterval(load, POLL_MS);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, []);

  return polled;
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

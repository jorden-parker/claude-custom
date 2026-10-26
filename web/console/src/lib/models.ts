import path from "node:path";
import { baseModelForSize, modelForSize } from "./size-models";
import { configuredSizes, consoleRepoDir } from "./sizes";
import { runOnce, type RunOnceOptions, type RunOnceResult } from "./run-once";

const DEFAULT_OLLAMA_URL = "http://localhost:11434";
const PROBE_TIMEOUT_MS = 3000;
const LIST_OPTIONS: RunOnceOptions = { timeoutMs: 10_000, maxBytes: 1024 * 1024 };
const PRUNABLE_CLASSES = new Set(["third-party", "orphan"]);
const LIST_LINE = /^(\S+)\s+(\S+)\s*$/;

type FetchLike = (url: string, init: { signal: AbortSignal }) => Promise<Response>;

export type ModelsDeps = {
  repoDir: string;
  ollamaUrl: string;
  runOnce: (argv: readonly string[], options: RunOnceOptions) => Promise<RunOnceResult>;
  fetch: FetchLike;
};

import type { InstalledModel, SizeStatus } from "./model-display";

export type ModelsSnapshot = {
  ollama: "up" | "down";
  sizes: SizeStatus[];
  models: InstalledModel[];
  prunable: string[];
};

export function modelsDeps(): ModelsDeps {
  return {
    repoDir: consoleRepoDir(),
    ollamaUrl: ollamaUrl(),
    runOnce,
    fetch: (url, init) => fetch(url, init),
  };
}

export function ollamaUrl(): string {
  const host = process.env.OLLAMA_HOST ?? "";
  if (host === "") {
    return DEFAULT_OLLAMA_URL;
  }
  return /^https?:\/\//.test(host) ? host : `http://${host}`;
}

export async function modelsSnapshot(deps: ModelsDeps): Promise<ModelsSnapshot> {
  const tags = await getJson(deps, "/api/tags");
  if (tags === null) {
    return { ollama: "down", sizes: [], models: [], prunable: [] };
  }
  const [running, listing] = await Promise.all([
    getJson(deps, "/api/ps"),
    deps.runOnce([path.join(deps.repoDir, "bin", "ollama-models"), "list"], LIST_OPTIONS),
  ]);
  const classes = classesFrom(listing.stdout);
  const sizes = bytesByName(tags);
  const loaded = new Set(entriesOf(running).map((entry) => String(entry.name)));
  const models = [...classes].map(([name, modelClass]) => ({
    name,
    class: modelClass,
    bytes: sizes.get(name) ?? 0,
    loaded: loaded.has(name),
  }));
  return {
    ollama: "up",
    sizes: configuredSizes(deps.repoDir).map((size) => sizeStatus(deps.repoDir, size, classes)),
    models,
    prunable: models.filter((model) => PRUNABLE_CLASSES.has(model.class)).map((model) => model.name),
  };
}

async function getJson(deps: ModelsDeps, route: string): Promise<unknown> {
  try {
    const response = await deps.fetch(`${deps.ollamaUrl}${route}`, {
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

function classesFrom(stdout: string): Map<string, string> {
  const classes = new Map<string, string>();
  for (const line of stdout.split("\n")) {
    const match = LIST_LINE.exec(line);
    if (match) {
      classes.set(match[2], match[1]);
    }
  }
  return classes;
}

function bytesByName(tags: unknown): Map<string, number> {
  return new Map(
    entriesOf(tags).map((entry) => [String(entry.name), typeof entry.size === "number" ? entry.size : 0]),
  );
}

function entriesOf(body: unknown): Record<string, unknown>[] {
  if (typeof body !== "object" || body === null || !("models" in body) || !Array.isArray(body.models)) {
    return [];
  }
  return body.models.filter((entry): entry is Record<string, unknown> => typeof entry === "object" && entry !== null);
}

function sizeStatus(repoDir: string, size: string, classes: Map<string, string>): SizeStatus {
  const model = modelForSize(repoDir, size);
  const modelClass = model === null ? undefined : (classes.get(model) ?? classes.get(`${model}:latest`));
  return {
    size,
    model,
    base: baseModelForSize(repoDir, size),
    installed: modelClass !== undefined,
    class: modelClass ?? null,
  };
}

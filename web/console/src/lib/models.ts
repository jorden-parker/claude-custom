import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { embeddingPreset, modelForSize, weightsFileForSize } from "./size-models";
import { configuredSizes, consoleRepoDir } from "./sizes";
import { runOnce, type RunOnceOptions, type RunOnceResult } from "./run-once";
import {
  findServerModel,
  listServerModels,
  modelServerUrl,
  type ServerModel,
  type ServerModelStatus,
} from "./model-server";
import type { FileState, SizeStatus, WeightFile } from "./model-display";

const LIST_OPTIONS: RunOnceOptions = { timeoutMs: 10_000, maxBytes: 1024 * 1024 };
const PRUNABLE_STATES = new Set<FileState>(["orphan", "partial"]);
const LIST_LINE = /^(pinned|mismatch|candidate|orphan|partial)\s+(\S+)(?:\s+(\S+))?\s*$/;
const PARTIAL_SUFFIX = ".part";

export type ModelsDeps = {
  repoDir: string;
  serverUrl: string;
  weightsDir: string;
  runOnce: (argv: readonly string[], options: RunOnceOptions) => Promise<RunOnceResult>;
};

export type EmbeddingStatus = {
  model: string | null;
  file: string | null;
  state: FileState | null;
  status: ServerModelStatus | null;
};

export type ModelsSnapshot = {
  server: "up" | "down";
  serverUrl: string;
  sizes: SizeStatus[];
  presets: ServerModel[];
  files: WeightFile[];
  prunable: string[];
  embedding: EmbeddingStatus;
};

type ListedFile = { name: string; state: FileState; size: string | null };

export function modelsDeps(): ModelsDeps {
  return {
    repoDir: consoleRepoDir(),
    serverUrl: modelServerUrl(),
    weightsDir: weightsDir(),
    runOnce,
  };
}

function weightsDir(): string {
  return process.env.CLAUDE_OLLAMA_WEIGHTS_DIR || path.join(os.homedir(), ".claude-ollama", "weights");
}

export async function modelsSnapshot(deps: ModelsDeps): Promise<ModelsSnapshot> {
  const [presets, listing] = await Promise.all([
    listServerModels(deps.serverUrl),
    deps.runOnce([path.join(deps.repoDir, "bin", "ollama-models"), "list"], LIST_OPTIONS),
  ]);
  const listed = parseWeightsListing(listing.stdout);
  const files = listed.map((file) => ({ ...file, bytes: fileBytes(path.join(deps.weightsDir, file.name)) }));
  return {
    server: presets === null ? "down" : "up",
    serverUrl: deps.serverUrl,
    sizes: configuredSizes(deps.repoDir).map((size) => sizeStatus(deps.repoDir, size, listed)),
    presets: presets ?? [],
    files,
    prunable: files.filter((file) => PRUNABLE_STATES.has(file.state)).map((file) => file.name),
    embedding: embeddingStatus(deps.repoDir, listed, presets ?? []),
  };
}

function parseWeightsListing(stdout: string): ListedFile[] {
  return stdout.split("\n").flatMap((line) => {
    const match = LIST_LINE.exec(line.trim());
    return match === null ? [] : [{ name: match[2], state: match[1] as FileState, size: match[3] ?? null }];
  });
}

function stateOfFile(listed: readonly ListedFile[], file: string | null): FileState | null {
  if (file === null) {
    return null;
  }
  const found = listed.find((entry) => entry.name === file || entry.name === `${file}${PARTIAL_SUFFIX}`);
  return found?.state ?? null;
}

function fileBytes(file: string): number {
  try {
    return fs.statSync(file).size;
  } catch {
    return 0;
  }
}

function sizeStatus(repoDir: string, size: string, listed: readonly ListedFile[]): SizeStatus {
  const file = weightsFileForSize(repoDir, size);
  return { size, model: modelForSize(repoDir, size), file, state: stateOfFile(listed, file) };
}

function embeddingStatus(
  repoDir: string,
  listed: readonly ListedFile[],
  presets: readonly ServerModel[],
): EmbeddingStatus {
  const preset = embeddingPreset(repoDir);
  if (preset === null) {
    return { model: null, file: null, state: null, status: null };
  }
  return {
    model: preset.model,
    file: preset.file,
    state: stateOfFile(listed, preset.file),
    status: findServerModel(presets, preset.model)?.status ?? null,
  };
}

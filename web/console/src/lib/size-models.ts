import { readFileSync } from "node:fs";
import { join } from "node:path";

const SIZE_NAME = /^[a-z0-9][a-z0-9-]*$/;

export function modelForSize(repoDir: string, size: string): string | null {
  if (!SIZE_NAME.test(size)) {
    return null;
  }
  try {
    const settings = JSON.parse(
      readFileSync(join(repoDir, "ollama", `settings.${size}.json`), "utf8"),
    ) as { model?: unknown };
    return typeof settings.model === "string" ? settings.model : null;
  } catch {
    return null;
  }
}

export type SizeSettings = { context: number | null; outputTokens: number | null; parameters: Record<string, number> };

export function sizeSettings(repoDir: string, size: string): SizeSettings {
  const entry = sizesEntry(repoDir, size);
  return {
    context: typeof entry?.context === "number" ? entry.context : null,
    outputTokens: typeof entry?.output_tokens === "number" ? entry.output_tokens : null,
    parameters: numericParameters(entry?.parameters),
  };
}

type SizesEntry = { context?: unknown; output_tokens?: unknown; parameters?: unknown; gguf?: unknown };

function sizesEntry(repoDir: string, size: string): SizesEntry | null {
  const sizes = readJsonRecord(join(repoDir, "ollama", "sizes.json"));
  return sizes !== null && Object.hasOwn(sizes, size) ? (sizes[size] as SizesEntry) : null;
}

function numericParameters(raw: unknown): Record<string, number> {
  if (typeof raw !== "object" || raw === null) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(raw).filter((entry): entry is [string, number] => typeof entry[1] === "number"),
  );
}

export function weightsFileForSize(repoDir: string, size: string): string | null {
  return ggufFileOf(sizesEntry(repoDir, size));
}

export type EmbeddingPreset = { model: string; file: string | null };

export function embeddingPreset(repoDir: string): EmbeddingPreset | null {
  const entry = readJsonRecord(join(repoDir, "ollama", "embedding.json"));
  if (entry === null || typeof entry.model !== "string") {
    return null;
  }
  return { model: entry.model, file: ggufFileOf(entry) };
}

function ggufFileOf(entry: { gguf?: unknown } | null): string | null {
  const gguf = entry?.gguf;
  if (typeof gguf !== "object" || gguf === null || !("file" in gguf)) {
    return null;
  }
  return typeof gguf.file === "string" ? gguf.file : null;
}

function readJsonRecord(file: string): Record<string, unknown> | null {
  try {
    const parsed: unknown = JSON.parse(readFileSync(file, "utf8"));
    return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

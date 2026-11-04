import { readFileSync } from "node:fs";
import { join } from "node:path";

const SIZE_NAME = /^[a-z0-9][a-z0-9-]*$/;
const FROM_LINE = /^FROM\s+(\S+)/m;

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

type SizesEntry = { context?: unknown; output_tokens?: unknown; parameters?: unknown };

function sizesEntry(repoDir: string, size: string): SizesEntry | null {
  try {
    const sizes = JSON.parse(readFileSync(join(repoDir, "ollama", "sizes.json"), "utf8")) as Record<string, SizesEntry>;
    return Object.hasOwn(sizes, size) ? sizes[size] : null;
  } catch {
    return null;
  }
}

function numericParameters(raw: unknown): Record<string, number> {
  if (typeof raw !== "object" || raw === null) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(raw).filter((entry): entry is [string, number] => typeof entry[1] === "number"),
  );
}

export function baseModelForSize(repoDir: string, size: string): string | null {
  if (!SIZE_NAME.test(size)) {
    return null;
  }
  try {
    const modelfile = readFileSync(join(repoDir, "ollama", `Modelfile.${size}`), "utf8");
    return FROM_LINE.exec(modelfile)?.[1] ?? null;
  } catch {
    return null;
  }
}

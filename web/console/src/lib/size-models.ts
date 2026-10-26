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

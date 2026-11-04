import fs from "node:fs";
import path from "node:path";

const SETTINGS_PREFIX = "settings.";
const SETTINGS_SUFFIX = ".json";
const SIZE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function consoleRepoDir(): string {
  return process.env.CLAUDE_CUSTOM_HOME ?? "";
}

export function listSizes(): string[] {
  return configuredSizes(consoleRepoDir());
}

export function configuredSizes(repoDir: string): string[] {
  const profileDir = path.join(repoDir, "ollama");
  if (repoDir === "" || !fs.existsSync(profileDir)) {
    return [];
  }
  const listedSizes = sizesJsonKeys(profileDir);
  return fs
    .readdirSync(profileDir)
    .filter((name) => name.startsWith(SETTINGS_PREFIX) && name.endsWith(SETTINGS_SUFFIX))
    .map((name) => name.slice(SETTINGS_PREFIX.length, -SETTINGS_SUFFIX.length))
    .filter((size) => SIZE_PATTERN.test(size) && listedSizes.has(size))
    .sort();
}

function sizesJsonKeys(profileDir: string): Set<string> {
  try {
    const parsed: unknown = JSON.parse(fs.readFileSync(path.join(profileDir, "sizes.json"), "utf8"));
    return new Set(parsed !== null && typeof parsed === "object" ? Object.keys(parsed) : []);
  } catch {
    return new Set();
  }
}

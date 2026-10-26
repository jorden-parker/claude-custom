import fs from "node:fs";
import path from "node:path";

const SETTINGS_PREFIX = "settings.";
const SETTINGS_SUFFIX = ".json";
const MODELFILE_PREFIX = "Modelfile.";
const SIZE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function consoleRepoDir(): string {
  return process.env.CLAUDE_CUSTOM_HOME ?? "";
}

export function configuredSizes(repoDir: string): string[] {
  const profileDir = path.join(repoDir, "ollama");
  if (repoDir === "" || !fs.existsSync(profileDir)) {
    return [];
  }
  return fs
    .readdirSync(profileDir)
    .filter((name) => name.startsWith(SETTINGS_PREFIX) && name.endsWith(SETTINGS_SUFFIX))
    .map((name) => name.slice(SETTINGS_PREFIX.length, -SETTINGS_SUFFIX.length))
    .filter((size) => SIZE_PATTERN.test(size) && isConfigured(profileDir, size))
    .sort();
}

function isConfigured(profileDir: string, size: string): boolean {
  return fs.existsSync(path.join(profileDir, `${SETTINGS_PREFIX}${size}${SETTINGS_SUFFIX}`)) &&
    fs.existsSync(path.join(profileDir, `${MODELFILE_PREFIX}${size}`));
}

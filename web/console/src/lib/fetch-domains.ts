import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseDomains, type DomainFile } from "./fetch-domain-rules";

const FILE_MODE = 0o600;
const FOLDER_MODE = 0o700;

export function fetchDomainsPath(): string {
  const configHome = process.env.XDG_CONFIG_HOME;
  const base = configHome ? configHome : path.join(os.homedir(), ".config");
  return path.join(base, "claude-custom", "fetch-domains");
}

export function readDomainsText(): string | null {
  try {
    return fs.readFileSync(fetchDomainsPath(), "utf8");
  } catch {
    return null;
  }
}

export function readDomains(): DomainFile {
  return parseDomains(readDomainsText() ?? "");
}

export function writeDomainsText(text: string): void {
  const file = fetchDomainsPath();
  const folder = path.dirname(file);
  fs.mkdirSync(folder, { recursive: true, mode: FOLDER_MODE });
  const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temporary, text, { mode: FILE_MODE });
  fs.renameSync(temporary, file);
}

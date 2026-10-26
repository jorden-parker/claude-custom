import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const FETCH_DOMAIN_PATTERN = /^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$/;

export const SUGGESTED_HOSTS: readonly string[] = [
  "docs.python.org",
  "pkg.go.dev",
  "go.dev",
  "developer.mozilla.org",
  "nodejs.org",
  "docs.rs",
];

export const MAX_FETCH_HOSTS = 200;

const FILE_MODE = 0o600;
const FOLDER_MODE = 0o700;

export type DomainFile = {
  hosts: string[];
  ignored: string[];
};

export type DomainPlan = {
  hosts: string[];
  text: string;
};

export function fetchDomainsPath(): string {
  const configHome = process.env.XDG_CONFIG_HOME;
  const base = configHome ? configHome : path.join(os.homedir(), ".config");
  return path.join(base, "claude-custom", "fetch-domains");
}

export function normalizeHost(text: string): string {
  return text.trim().toLowerCase();
}

export function isValidHost(host: string): boolean {
  return FETCH_DOMAIN_PATTERN.test(host);
}

export function parseDomains(text: string): DomainFile {
  const hosts: string[] = [];
  const ignored: string[] = [];
  for (const line of text.split("\n")) {
    const host = normalizeHost(line);
    if (host === "") {
      continue;
    }
    if (!isValidHost(host)) {
      ignored.push(host);
    } else if (!hosts.includes(host)) {
      hosts.push(host);
    }
  }
  return { hosts, ignored };
}

export function planDomains(hosts: string[]): DomainPlan {
  const planned: string[] = [];
  for (const raw of hosts) {
    const host = normalizeHost(raw);
    if (!isValidHost(host)) {
      throw new Error(`not a hostname: ${host}`);
    }
    if (!planned.includes(host)) {
      planned.push(host);
    }
  }
  return { hosts: planned, text: planned.map((host) => `${host}\n`).join("") };
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

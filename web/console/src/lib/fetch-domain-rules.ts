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

export type DomainFile = {
  hosts: string[];
  ignored: string[];
};

export type DomainPlan = {
  hosts: string[];
  text: string;
};

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

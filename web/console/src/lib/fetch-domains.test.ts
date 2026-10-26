import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  FETCH_DOMAIN_PATTERN,
  SUGGESTED_HOSTS,
  fetchDomainsPath,
  isValidHost,
  normalizeHost,
  parseDomains,
  planDomains,
  readDomains,
  readDomainsText,
  writeDomainsText,
} from "./fetch-domains";

describe("isValidHost", () => {
  it.each(["docs.python.org", "go.dev", "a-b.example.co", "x1.y2.z3"])("accepts %s", (host) => {
    expect(isValidHost(host)).toBe(true);
  });

  it.each(["localhost", "127.0.0.1", "*.example.com", "example.com/path", "-a.com", "a.com.", "UPPER.com", "a..b.com"])(
    "rejects %s",
    (host) => {
      expect(isValidHost(host)).toBe(false);
    },
  );
});

describe("FETCH_DOMAIN_PATTERN", () => {
  it("is the launcher's pattern", () => {
    expect(FETCH_DOMAIN_PATTERN.source).toBe("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z][a-z0-9-]*[a-z0-9]$");
  });
});

describe("SUGGESTED_HOSTS", () => {
  it("lists only valid hostnames", () => {
    for (const host of SUGGESTED_HOSTS) {
      expect(isValidHost(host)).toBe(true);
    }
  });
});

describe("normalizeHost", () => {
  it("trims and lowercases", () => {
    expect(normalizeHost("  Docs.Python.ORG \n")).toBe("docs.python.org");
  });
});

describe("parseDomains", () => {
  it("keeps valid hosts in file order, skipping blanks and duplicates", () => {
    const parsed = parseDomains("go.dev\n\n  Docs.Python.org \ngo.dev\n");

    expect(parsed).toEqual({ hosts: ["go.dev", "docs.python.org"], ignored: [] });
  });

  it("reports invalid lines as ignored", () => {
    const parsed = parseDomains("localhost\ngo.dev\n*.example.com\n");

    expect(parsed).toEqual({ hosts: ["go.dev"], ignored: ["localhost", "*.example.com"] });
  });
});

describe("planDomains", () => {
  it("normalizes, dedupes and renders one host per line ending with a newline", () => {
    expect(planDomains([" Go.dev", "docs.rs", "go.dev"])).toEqual({
      hosts: ["go.dev", "docs.rs"],
      text: "go.dev\ndocs.rs\n",
    });
  });

  it("plans an empty file for no hosts", () => {
    expect(planDomains([])).toEqual({ hosts: [], text: "" });
  });

  it("refuses an invalid host", () => {
    expect(() => planDomains(["go.dev", "localhost"])).toThrow("not a hostname: localhost");
  });
});

describe("fetch domains file", () => {
  let configHome: string;
  let previousConfigHome: string | undefined;

  beforeEach(() => {
    configHome = fs.mkdtempSync(path.join(os.tmpdir(), "fetch-domains-"));
    previousConfigHome = process.env.XDG_CONFIG_HOME;
    process.env.XDG_CONFIG_HOME = configHome;
  });

  afterEach(() => {
    if (previousConfigHome === undefined) {
      delete process.env.XDG_CONFIG_HOME;
    } else {
      process.env.XDG_CONFIG_HOME = previousConfigHome;
    }
    fs.rmSync(configHome, { recursive: true, force: true });
  });

  it("lives under XDG_CONFIG_HOME", () => {
    expect(fetchDomainsPath()).toBe(path.join(configHome, "claude-custom", "fetch-domains"));
  });

  it("reads an empty list when the file is missing", () => {
    expect(readDomains()).toEqual({ hosts: [], ignored: [] });
  });

  it("reads no text when the file is missing", () => {
    expect(readDomainsText()).toBeNull();
  });

  it("writes the text and reads the hosts back", () => {
    writeDomainsText("docs.python.org\ngo.dev\n");

    expect(fs.readFileSync(fetchDomainsPath(), "utf8")).toBe("docs.python.org\ngo.dev\n");
    expect(readDomains().hosts).toEqual(["docs.python.org", "go.dev"]);
  });

  it("writes with mode 0600 inside a 0700 folder", () => {
    writeDomainsText("go.dev\n");

    expect(fs.statSync(fetchDomainsPath()).mode & 0o777).toBe(0o600);
    expect(fs.statSync(path.dirname(fetchDomainsPath())).mode & 0o777).toBe(0o700);
  });

  it("leaves no temporary file behind", () => {
    writeDomainsText("go.dev\n");

    expect(fs.readdirSync(path.dirname(fetchDomainsPath()))).toEqual(["fetch-domains"]);
  });

  it("replaces an existing file", () => {
    writeDomainsText("go.dev\n");
    writeDomainsText("docs.rs\n");

    expect(readDomainsText()).toBe("docs.rs\n");
  });
});

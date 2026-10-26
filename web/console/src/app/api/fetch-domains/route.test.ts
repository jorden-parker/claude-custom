import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listHistory } from "@/lib/history";
import { GET, PUT } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const jsonRequest = (body: unknown) =>
  new Request("http://127.0.0.1:8808/api/fetch-domains", {
    method: "PUT",
    headers: { "content-type": "application/json", origin: "http://127.0.0.1:8808" },
    body: JSON.stringify(body),
  });

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}

describe("/api/fetch-domains", () => {
  let configHome: string;
  let stateDir: string;
  let previous: { xdg?: string; state?: string };

  beforeEach(() => {
    configHome = fs.mkdtempSync(path.join(os.tmpdir(), "fetch-domains-route-"));
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "fetch-domains-state-"));
    previous = { xdg: process.env.XDG_CONFIG_HOME, state: process.env.CLAUDE_CONSOLE_STATE_DIR };
    process.env.XDG_CONFIG_HOME = configHome;
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
  });

  afterEach(() => {
    restoreEnv("XDG_CONFIG_HOME", previous.xdg);
    restoreEnv("CLAUDE_CONSOLE_STATE_DIR", previous.state);
    fs.rmSync(configHome, { recursive: true, force: true });
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("answers the empty list with the suggested hosts", async () => {
    const body = await (await GET()).json();

    expect(body).toMatchObject({ hosts: [], ignored: [], suggested: expect.arrayContaining(["docs.rs"]) });
    expect(body.path).toBe(path.join(configHome, "claude-custom", "fetch-domains"));
  });

  it("saves the hosts and answers the new state", async () => {
    const response = await PUT(jsonRequest({ hosts: ["Docs.Python.org", "go.dev"] }));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ hosts: ["docs.python.org", "go.dev"], ignored: [] });
    expect(fs.readFileSync(path.join(configHome, "claude-custom", "fetch-domains"), "utf8")).toBe(
      "docs.python.org\ngo.dev\n",
    );
  });

  it("records the save in the shared history as fetch-domains", async () => {
    await PUT(jsonRequest({ hosts: ["go.dev"] }));

    const entries = listHistory();
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ kind: "fetch-domains", source: "console", before: null });
  });

  it("records nothing when the saved hosts are unchanged", async () => {
    await PUT(jsonRequest({ hosts: ["go.dev"] }));
    await PUT(jsonRequest({ hosts: ["go.dev"] }));

    expect(listHistory()).toHaveLength(1);
  });

  it("rejects an invalid host with 400 naming it, and writes nothing", async () => {
    const response = await PUT(jsonRequest({ hosts: ["go.dev", "localhost"] }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ message: "not a hostname: localhost" });
    expect(fs.existsSync(path.join(configHome, "claude-custom", "fetch-domains"))).toBe(false);
  });

  it("rejects more than 200 hosts with 400", async () => {
    const hosts = Array.from({ length: 201 }, (_, index) => `site${index}.example.com`);

    const response = await PUT(jsonRequest({ hosts }));

    expect(response.status).toBe(400);
  });

  it("rejects a body without a hosts list with 400", async () => {
    const response = await PUT(jsonRequest({ domains: ["go.dev"] }));

    expect(response.status).toBe(400);
  });

  it("rejects a body that is not JSON with 400", async () => {
    const response = await PUT(
      new Request("http://127.0.0.1:8808/api/fetch-domains", {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: "{not json",
      }),
    );

    expect(response.status).toBe(400);
  });

  it("rejects a body that is not declared JSON with 415", async () => {
    const response = await PUT(
      new Request("http://127.0.0.1:8808/api/fetch-domains", {
        method: "PUT",
        headers: { "content-type": "text/plain" },
        body: JSON.stringify({ hosts: ["go.dev"] }),
      }),
    );

    expect(response.status).toBe(415);
  });
});

import fs from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { makeFixtureRepo, type FixtureRepo } from "@/lib/profile-fixture";
import { profileFilePath } from "@/lib/profiles";
import { GET, PUT } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const ORIGIN = "http://127.0.0.1:8808";

function context(id: string) {
  return { params: Promise.resolve({ id }) };
}

function putRequest(id: string, body: unknown): Request {
  return new Request(`${ORIGIN}/api/profiles/${id}`, {
    method: "PUT",
    headers: { "content-type": "application/json", origin: ORIGIN },
    body: JSON.stringify(body),
  });
}

describe("/api/profiles/[id]", () => {
  let fixture: FixtureRepo;
  const previous: Record<string, string | undefined> = {};

  beforeEach(() => {
    fixture = makeFixtureRepo();
    for (const [name, value] of [
      ["XDG_CONFIG_HOME", fixture.configHome],
      ["CLAUDE_CONSOLE_STATE_DIR", fixture.stateDir],
      ["CLAUDE_CUSTOM_HOME", fixture.repoDir],
    ]) {
      previous[name] = process.env[name];
      process.env[name] = value;
    }
  });

  afterEach(() => {
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = value;
      }
    }
    fixture.cleanup();
  });

  it("returns the override and the base view for claude-code", async () => {
    const response = await GET(new Request(ORIGIN), context("claude-code"));
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.title).toBe("Claude Code");
    expect(body.override).toEqual({});
    expect(body.base.tools.map((tool: { name: string }) => tool.name)).toEqual(["Bash", "WebFetch", "Agent"]);
    expect(body.base.mcpServers).toEqual([]);
  });

  it("returns the Ollama base with context, parameters, hooks and MCP servers", async () => {
    const response = await GET(new Request(ORIGIN), context("ollama-27b"));
    const body = await response.json();

    expect(body.model).toBe("qwen3.8-27b-cc");
    expect(body.base.context).toBe(65536);
    expect(body.base.outputTokens).toBe(8192);
    expect(body.base.parameters).toEqual({ temperature: 0.7 });
    expect(body.base.hooks).toEqual([{ event: "Stop", matcher: "*", command: "stop-verify.py" }]);
    expect(body.base.mcpServers).toEqual(["code-search", "repo", "dev"]);
  });

  it("answers 404 for a profile that is not configured", async () => {
    const response = await GET(new Request(ORIGIN), context("ollama-99b"));

    expect(response.status).toBe(404);
  });

  it("saves a valid override and reads it back", async () => {
    const response = await PUT(putRequest("claude-code", { tools: { WebFetch: "deny" } }), context("claude-code"));

    expect(response.status).toBe(200);
    expect(JSON.parse(fs.readFileSync(profileFilePath("claude-code"), "utf8"))).toEqual({
      tools: { WebFetch: "deny" },
    });
  });

  it("deletes the file when the body is empty", async () => {
    await PUT(putRequest("claude-code", { sandbox: false }), context("claude-code"));
    const response = await PUT(putRequest("claude-code", {}), context("claude-code"));

    expect(response.status).toBe(200);
    expect(fs.existsSync(profileFilePath("claude-code"))).toBe(false);
  });

  it("answers 400 with the rule message for an invalid override", async () => {
    const response = await PUT(putRequest("claude-code", { tools: { Nope: "allow" } }), context("claude-code"));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ message: "unknown tool Nope" });
    expect(fs.existsSync(profileFilePath("claude-code"))).toBe(false);
  });

  it("refuses sandbox on an Ollama profile", async () => {
    const response = await PUT(putRequest("ollama-27b", { sandbox: false }), context("ollama-27b"));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ message: "sandbox is always on for Ollama profiles" });
  });

  it("answers 404 when saving an unknown profile", async () => {
    const response = await PUT(putRequest("ollama-99b", {}), context("ollama-99b"));

    expect(response.status).toBe(404);
  });
});

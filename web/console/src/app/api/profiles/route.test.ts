import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { makeFixtureRepo, type FixtureRepo } from "@/lib/profile-fixture";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

describe("/api/profiles", () => {
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

  it("lists claude-code and each configured size with its model and context", async () => {
    const response = await GET();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.profiles).toEqual([
      { id: "claude-code", title: "Claude Code", kind: "claude-code", model: null, context: null, overrides: 0 },
      { id: "ollama-27b", title: "Ollama 27b", kind: "ollama", model: "qwen3.8-27b-cc", context: 65536, overrides: 0 },
    ]);
  });
});

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { modelsSnapshot, type ModelsDeps } from "./models";
import type { RunOnceResult } from "./run-once";

const LISTING = [
  "profile      qwen3.8-27b-cc",
  "mismatch     qwen3.6-35b-cc",
  "third-party  someone/model:latest",
  "orphan       old-cc:latest",
].join("\n");

const TAGS = {
  models: [
    { name: "qwen3.8-27b-cc", size: 18_000_000_000 },
    { name: "qwen3.6-35b-cc", size: 20_000_000_000 },
    { name: "someone/model:latest", size: 2_000_000_000 },
    { name: "old-cc:latest", size: 1_000_000_000 },
  ],
};

const PS = { models: [{ name: "qwen3.8-27b-cc", size_vram: 18_000_000_000 }] };

describe("modelsSnapshot", () => {
  let repo: string;
  let argvs: string[][];

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "models-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    writeSize("27b", "qwen3.8-27b-cc", "qwen3.8:27b-mlx");
    writeSize("35b", "qwen3.6-35b-cc", "qwen3.6:35b-mlx");
    argvs = [];
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  function writeSize(size: string, model: string, base: string) {
    fs.writeFileSync(path.join(repo, "ollama", `settings.${size}.json`), JSON.stringify({ model }));
    fs.writeFileSync(path.join(repo, "ollama", `Modelfile.${size}`), `FROM ${base}\n`);
  }

  function deps(overrides: Partial<ModelsDeps> = {}): ModelsDeps {
    return {
      repoDir: repo,
      ollamaUrl: "http://localhost:11434",
      runOnce: async (argv): Promise<RunOnceResult> => {
        argvs.push([...argv]);
        return { code: 0, stdout: LISTING, stderr: "" };
      },
      fetch: fakeFetch({ "/api/tags": TAGS, "/api/ps": PS }),
      ...overrides,
    };
  }

  it("merges sizes, installed models and prunable names", async () => {
    const snapshot = await modelsSnapshot(deps());

    expect(argvs).toEqual([[`${repo}/bin/ollama-models`, "list"]]);
    expect(snapshot.ollama).toBe("up");
    expect(snapshot.sizes).toEqual([
      { size: "27b", model: "qwen3.8-27b-cc", base: "qwen3.8:27b-mlx", installed: true, class: "profile" },
      { size: "35b", model: "qwen3.6-35b-cc", base: "qwen3.6:35b-mlx", installed: true, class: "mismatch" },
    ]);
    expect(snapshot.models).toEqual([
      { name: "qwen3.8-27b-cc", class: "profile", bytes: 18_000_000_000, loaded: true },
      { name: "qwen3.6-35b-cc", class: "mismatch", bytes: 20_000_000_000, loaded: false },
      { name: "someone/model:latest", class: "third-party", bytes: 2_000_000_000, loaded: false },
      { name: "old-cc:latest", class: "orphan", bytes: 1_000_000_000, loaded: false },
    ]);
    expect(snapshot.prunable).toEqual(["someone/model:latest", "old-cc:latest"]);
  });

  it("marks a size missing when its model is not in the list", async () => {
    const snapshot = await modelsSnapshot(deps({ runOnce: async () => ({ code: 0, stdout: "", stderr: "" }) }));

    expect(snapshot.sizes[0]).toEqual({
      size: "27b",
      model: "qwen3.8-27b-cc",
      base: "qwen3.8:27b-mlx",
      installed: false,
      class: null,
    });
  });

  it("matches a size model with or without the :latest tag", async () => {
    const listing = "profile      qwen3.8-27b-cc:latest";
    const snapshot = await modelsSnapshot(deps({ runOnce: async () => ({ code: 0, stdout: listing, stderr: "" }) }));

    expect(snapshot.sizes[0]).toMatchObject({ installed: true, class: "profile" });
  });

  it("does not match a different tag of the size model", async () => {
    const listing = "profile      qwen3.8-27b-cc:7b";
    const snapshot = await modelsSnapshot(deps({ runOnce: async () => ({ code: 0, stdout: listing, stderr: "" }) }));

    expect(snapshot.sizes[0]?.installed).toBe(false);
  });

  it("reports Ollama as down with empty lists when it does not answer", async () => {
    const snapshot = await modelsSnapshot(deps({ fetch: async () => { throw new TypeError("fetch failed"); } }));

    expect(snapshot).toEqual({ ollama: "down", sizes: [], models: [], prunable: [] });
    expect(argvs).toEqual([]);
  });

  it("asks Ollama with the configured URL", async () => {
    const urls: string[] = [];
    await modelsSnapshot(deps({ ollamaUrl: "http://127.0.0.1:9999", fetch: fakeFetch({ "/api/tags": TAGS, "/api/ps": PS }, urls) }));

    expect(urls).toContain("http://127.0.0.1:9999/api/tags");
  });
});

function fakeFetch(routes: Record<string, unknown>, seen: string[] = []): ModelsDeps["fetch"] {
  return async (url) => {
    seen.push(url);
    const route = new URL(url).pathname;
    if (!(route in routes)) {
      throw new Error(`no route ${route}`);
    }
    return Response.json(routes[route]);
  };
}

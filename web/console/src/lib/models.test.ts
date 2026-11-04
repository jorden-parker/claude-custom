import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { modelsSnapshot, type ModelsDeps } from "./models";
import type { RunOnceResult } from "./run-once";
import { closedPortUrl, startStubLlama, STUB_MODELS, type StubLlama } from "./stub-llama-test-support";

const LISTING = [
  "pinned   Qwen3.8-27B-UD-Q4_K_XL.gguf 27b",
  "mismatch Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf 35b",
  "candidate    Qwen3.8-27B-UD-Q4_K_XL.gguf.next",
  "orphan   Old-Model-Q4_K_M.gguf",
  "partial  Half-Model.gguf.part",
  "a line that is not a listing",
].join("\n");

describe("modelsSnapshot", () => {
  let repo: string;
  let weights: string;
  let argvs: string[][];
  let stub: StubLlama | null;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "models-"));
    weights = path.join(repo, "weights");
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.mkdirSync(weights);
    fs.writeFileSync(path.join(weights, "Qwen3.8-27B-UD-Q4_K_XL.gguf"), "x".repeat(2048));
    fs.writeFileSync(path.join(weights, "Old-Model-Q4_K_M.gguf"), "x".repeat(512));
    writeSizes({
      "27b": { model: "qwen3.8-27b-cc", file: "Qwen3.8-27B-UD-Q4_K_XL.gguf" },
      "35b": { model: "qwen3.6-35b-cc", file: "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf" },
    });
    fs.writeFileSync(
      path.join(repo, "ollama", "embedding.json"),
      JSON.stringify({ model: "qwen3-embedding:0.6b", gguf: { file: "Qwen3-Embedding-0.6B-Q8_0.gguf" } }),
    );
    argvs = [];
    stub = null;
  });

  afterEach(async () => {
    await stub?.stop();
    fs.rmSync(repo, { recursive: true, force: true });
  });

  function writeSizes(sizes: Record<string, { model: string; file: string }>) {
    const entries = Object.entries(sizes).map(([size, { model, file }]) => {
      fs.writeFileSync(path.join(repo, "ollama", `settings.${size}.json`), JSON.stringify({ model }));
      fs.writeFileSync(path.join(repo, "ollama", `Modelfile.${size}`), `FROM ./weights/${file}\n`);
      return [size, { model, gguf: { file } }];
    });
    fs.writeFileSync(path.join(repo, "ollama", "sizes.json"), JSON.stringify(Object.fromEntries(entries)));
  }

  async function deps(overrides: Partial<ModelsDeps> = {}): Promise<ModelsDeps> {
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3.8-27b-cc"] });
    return {
      repoDir: repo,
      serverUrl: stub.url,
      weightsDir: weights,
      runOnce: async (argv): Promise<RunOnceResult> => {
        argvs.push([...argv]);
        return { code: 0, stdout: LISTING, stderr: "" };
      },
      ...overrides,
    };
  }

  it("joins the sizes, the server's presets and the weight files", async () => {
    const snapshot = await modelsSnapshot(await deps());

    expect(argvs).toEqual([[`${repo}/bin/ollama-models`, "list"]]);
    expect(snapshot.server).toBe("up");
    expect(snapshot.serverUrl).toBe(stub?.url);
    expect(snapshot.sizes).toEqual([
      { size: "27b", model: "qwen3.8-27b-cc", file: "Qwen3.8-27B-UD-Q4_K_XL.gguf", state: "pinned" },
      { size: "35b", model: "qwen3.6-35b-cc", file: "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf", state: "mismatch" },
    ]);
    expect(snapshot.presets).toEqual([
      { id: "qwen3.8-27b-cc", aliases: [], status: "loaded", bytes: 17_000_000_000 },
      { id: "qwen3.8-27b-cc@think", aliases: [], status: "unloaded", bytes: null },
      { id: "qwen3-embedding-0.6b", aliases: ["qwen3-embedding:0.6b"], status: "unloaded", bytes: null },
    ]);
    expect(snapshot.files).toEqual([
      { name: "Qwen3.8-27B-UD-Q4_K_XL.gguf", state: "pinned", size: "27b", bytes: 2048 },
      { name: "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf", state: "mismatch", size: "35b", bytes: 0 },
      { name: "Qwen3.8-27B-UD-Q4_K_XL.gguf.next", state: "candidate", size: null, bytes: 0 },
      { name: "Old-Model-Q4_K_M.gguf", state: "orphan", size: null, bytes: 512 },
      { name: "Half-Model.gguf.part", state: "partial", size: null, bytes: 0 },
    ]);
    expect(snapshot.prunable).toEqual(["Old-Model-Q4_K_M.gguf", "Half-Model.gguf.part"]);
  });

  it("marks a size missing when its file is not listed", async () => {
    const snapshot = await modelsSnapshot(await deps({ runOnce: async () => ({ code: 0, stdout: "", stderr: "" }) }));

    expect(snapshot.sizes[0]).toEqual({
      size: "27b",
      model: "qwen3.8-27b-cc",
      file: "Qwen3.8-27B-UD-Q4_K_XL.gguf",
      state: null,
    });
  });

  it("matches a size's half-downloaded file as partial", async () => {
    const listing = "partial Qwen3.8-27B-UD-Q4_K_XL.gguf.part 27b";
    const snapshot = await modelsSnapshot(await deps({ runOnce: async () => ({ code: 0, stdout: listing, stderr: "" }) }));

    expect(snapshot.sizes[0]?.state).toBe("partial");
  });

  it("reports the embedding preset's file state and server status by its alias", async () => {
    const listing = "pinned Qwen3-Embedding-0.6B-Q8_0.gguf embedding";
    const snapshot = await modelsSnapshot(await deps({ runOnce: async () => ({ code: 0, stdout: listing, stderr: "" }) }));

    expect(snapshot.embedding).toEqual({
      model: "qwen3-embedding:0.6b",
      file: "Qwen3-Embedding-0.6B-Q8_0.gguf",
      state: "pinned",
      status: "unloaded",
    });
  });

  it("reports no embedding without an embedding file", async () => {
    fs.rmSync(path.join(repo, "ollama", "embedding.json"));

    const snapshot = await modelsSnapshot(await deps());

    expect(snapshot.embedding).toEqual({ model: null, file: null, state: null, status: null });
  });

  it("keeps the files and sizes but lists no presets when the server is down", async () => {
    const snapshot = await modelsSnapshot(await deps({ serverUrl: await closedPortUrl() }));

    expect(snapshot.server).toBe("down");
    expect(snapshot.presets).toEqual([]);
    expect(snapshot.sizes).toHaveLength(2);
    expect(snapshot.files).toHaveLength(5);
    expect(snapshot.embedding.status).toBeNull();
  });
});

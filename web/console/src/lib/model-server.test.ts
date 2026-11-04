import { afterEach, describe, expect, it } from "vitest";
import {
  changeModel,
  listServerModels,
  modelServerUrl,
  parseServerModels,
  serverBuild,
} from "./model-server";
import { closedPortUrl, startStubLlama, STUB_MODELS, type StubLlama } from "./stub-llama-test-support";

describe("modelServerUrl", () => {
  it("defaults to the llama-server port on the loopback address", () => {
    expect(modelServerUrl({})).toBe("http://127.0.0.1:11435");
  });

  it("takes LLAMA_SERVER_URL without a trailing slash", () => {
    expect(modelServerUrl({ LLAMA_SERVER_URL: "http://127.0.0.1:9999/" })).toBe("http://127.0.0.1:9999");
  });

  it("falls back to the default when LLAMA_SERVER_URL is blank", () => {
    expect(modelServerUrl({ LLAMA_SERVER_URL: "  " })).toBe("http://127.0.0.1:11435");
  });
});

describe("the model server client", () => {
  let stub: StubLlama | null = null;

  afterEach(async () => {
    await stub?.stop();
    stub = null;
  });

  it("lists each preset with its aliases, status and weights bytes", async () => {
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3.8-27b-cc"] });

    expect(await listServerModels(stub.url)).toEqual([
      { id: "qwen3.8-27b-cc", aliases: [], status: "loaded", bytes: 17_000_000_000 },
      { id: "qwen3.8-27b-cc@think", aliases: [], status: "unloaded", bytes: null },
      { id: "qwen3-embedding-0.6b", aliases: ["qwen3-embedding:0.6b"], status: "unloaded", bytes: null },
    ]);
  });

  it("reports a model that is still loading", async () => {
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3.8-27b-cc"], loading: { "qwen3.8-27b-cc": 3 } });

    const [first] = (await listServerModels(stub.url)) ?? [];

    expect(first).toMatchObject({ id: "qwen3.8-27b-cc", status: "loading" });
  });

  it("gives null when the server does not answer", async () => {
    expect(await listServerModels(await closedPortUrl())).toBeNull();
  });

  it("gives null when /models fails", async () => {
    stub = await startStubLlama({ models: STUB_MODELS, fail_paths: ["/models"] });

    expect(await listServerModels(stub.url)).toBeNull();
  });

  it("reads the build from /props", async () => {
    stub = await startStubLlama({ build: 11500, commit: "abc1234" });

    expect(await serverBuild(stub.url)).toBe("b11500-abc1234");
  });

  it("gives a null build when /props fails", async () => {
    stub = await startStubLlama({ fail_paths: ["/props"] });

    expect(await serverBuild(stub.url)).toBeNull();
  });

  it("posts a load and an unload with the model id", async () => {
    stub = await startStubLlama({ models: STUB_MODELS });

    expect(await changeModel(stub.url, "load", "qwen3.8-27b-cc")).toEqual({ ok: true });
    expect(stub.state().loaded).toEqual(["qwen3.8-27b-cc"]);
    expect(await changeModel(stub.url, "unload", "qwen3.8-27b-cc")).toEqual({ ok: true });
    expect(stub.state().loaded).toEqual([]);
    expect(stub.requests().filter((request) => request.method === "POST")).toEqual([
      { method: "POST", path: "/models/load", body: { model: "qwen3.8-27b-cc" } },
      { method: "POST", path: "/models/unload", body: { model: "qwen3.8-27b-cc" } },
    ]);
  });

  it("passes the server's error message back when an action fails", async () => {
    stub = await startStubLlama({ models: STUB_MODELS });

    expect(await changeModel(stub.url, "unload", "qwen3.8-27b-cc")).toEqual({
      ok: false,
      message: "model is not running",
    });
  });

  it("says the server is down when an action cannot reach it", async () => {
    const url = await closedPortUrl();

    expect(await changeModel(url, "load", "qwen3.8-27b-cc")).toEqual({
      ok: false,
      message: `the model server at ${url} did not answer`,
    });
  });
});

describe("parseServerModels", () => {
  it("leaves out models the router found in the Hugging Face cache", () => {
    expect(
      parseServerModels({
        data: [
          { id: "qwen3.8-27b-cc", aliases: [], status: { value: "unloaded" }, source: "preset" },
          { id: "unsloth/Qwen3-0.6B-GGUF:Q4_K_M", aliases: [], status: { value: "unloaded" }, source: "cache" },
        ],
      }),
    ).toEqual([{ id: "qwen3.8-27b-cc", aliases: [], status: "unloaded", bytes: null }]);
  });

  it("skips entries without an id or a known status", () => {
    expect(
      parseServerModels({
        data: [{ aliases: [] }, { id: "a", status: { value: "sleeping" } }, { id: "b", status: { value: "loaded" }, meta: { size: 5 } }],
      }),
    ).toEqual([{ id: "b", aliases: [], status: "loaded", bytes: 5 }]);
  });

  it("gives null for a body without a data list", () => {
    expect(parseServerModels({ models: [] })).toBeNull();
    expect(parseServerModels(null)).toBeNull();
  });
});

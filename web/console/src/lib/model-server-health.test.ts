import { afterEach, describe, expect, it } from "vitest";
import { modelServerHealth } from "./model-server-health";
import { closedPortUrl, startStubLlama, STUB_MODELS, type StubLlama } from "./stub-llama-test-support";

describe("modelServerHealth", () => {
  let stub: StubLlama | null = null;

  afterEach(async () => {
    await stub?.stop();
    stub = null;
  });

  it("is up with the build when /health answers and no model is loading", async () => {
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3.8-27b-cc"] });

    expect(await modelServerHealth({ LLAMA_SERVER_URL: stub.url })).toEqual({
      state: "up",
      url: stub.url,
      build: "b11429-d81235049",
    });
  });

  it("is loading while a model's status is loading", async () => {
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3.8-27b-cc"], loading: { "qwen3.8-27b-cc": 3 } });

    expect(await modelServerHealth({ LLAMA_SERVER_URL: stub.url })).toMatchObject({ state: "loading" });
  });

  it("is loading when /health answers 503", async () => {
    stub = await startStubLlama({ models: STUB_MODELS, health_status: 503 });

    expect(await modelServerHealth({ LLAMA_SERVER_URL: stub.url })).toMatchObject({ state: "loading" });
  });

  it("is down when /health fails another way", async () => {
    stub = await startStubLlama({ fail_paths: ["/health"] });

    expect(await modelServerHealth({ LLAMA_SERVER_URL: stub.url })).toMatchObject({ state: "down" });
  });

  it("is down with no build when nothing listens on that port", async () => {
    const url = await closedPortUrl();

    expect(await modelServerHealth({ LLAMA_SERVER_URL: url })).toEqual({ state: "down", url, build: null });
  });
});

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { startStubLlama, STUB_MODELS, type StubLlama } from "@/lib/stub-llama-test-support";
import { POST } from "./route";

function post(model: string) {
  return POST(
    new Request("http://127.0.0.1/api/models/unload", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model }),
    }),
  );
}

describe("POST /api/models/unload", () => {
  let stub: StubLlama;

  beforeEach(async () => {
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3.8-27b-cc"] });
    process.env.LLAMA_SERVER_URL = stub.url;
  });

  afterEach(async () => {
    delete process.env.LLAMA_SERVER_URL;
    await stub.stop();
  });

  it("unloads a loaded model", async () => {
    const response = await post("qwen3.8-27b-cc");

    expect(response.status).toBe(200);
    expect(stub.state().loaded).toEqual([]);
  });

  it("matches a model by its alias", async () => {
    await stub.stop();
    stub = await startStubLlama({ models: STUB_MODELS, loaded: ["qwen3-embedding-0.6b"] });
    process.env.LLAMA_SERVER_URL = stub.url;

    const response = await post("qwen3-embedding:0.6b");

    expect(response.status).toBe(200);
    expect(stub.state().loaded).toEqual([]);
  });

  it("answers 502 with the server's message when the model is not running", async () => {
    await post("qwen3.8-27b-cc");

    const response = await post("qwen3.8-27b-cc");

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ message: "model is not running" });
  });
});

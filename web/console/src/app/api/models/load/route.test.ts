import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { closedPortUrl, startStubLlama, STUB_MODELS, type StubLlama } from "@/lib/stub-llama-test-support";
import { POST } from "./route";

function post(body: unknown, contentType = "application/json") {
  return POST(
    new Request("http://127.0.0.1/api/models/load", {
      method: "POST",
      headers: { "Content-Type": contentType },
      body: typeof body === "string" ? body : JSON.stringify(body),
    }),
  );
}

describe("POST /api/models/load", () => {
  let stub: StubLlama;

  beforeEach(async () => {
    stub = await startStubLlama({ models: STUB_MODELS });
    process.env.LLAMA_SERVER_URL = stub.url;
  });

  afterEach(async () => {
    delete process.env.LLAMA_SERVER_URL;
    await stub.stop();
  });

  it("loads a model the server lists", async () => {
    const response = await post({ model: "qwen3.8-27b-cc@think" });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    expect(stub.state().loaded).toEqual(["qwen3.8-27b-cc@think"]);
  });

  it("refuses an id the server does not list, without posting it", async () => {
    const response = await post({ model: "someone/else:latest" });

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ message: "someone/else:latest is not a model the server lists" });
    expect(stub.requests().some((request) => request.path === "/models/load")).toBe(false);
  });

  it("refuses a body without a model id", async () => {
    for (const body of [{}, { model: 7 }, { model: "" }, "not json"]) {
      expect((await post(body)).status).toBe(400);
    }
  });

  it("refuses a body that is not JSON", async () => {
    expect((await post({ model: "qwen3.8-27b-cc" }, "text/plain")).status).toBe(415);
  });

  it("answers 502 when the server does not answer", async () => {
    process.env.LLAMA_SERVER_URL = await closedPortUrl();

    expect((await post({ model: "qwen3.8-27b-cc" })).status).toBe(502);
  });
});

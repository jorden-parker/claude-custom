import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ollamaIsUp } from "./ollama-health";

describe("ollamaIsUp", () => {
  let server: http.Server;
  let port: number;

  beforeEach(async () => {
    server = http.createServer((request, response) => {
      response.end(request.url === "/api/version" ? '{"version":"0.0.0"}' : "");
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    port = (server.address() as AddressInfo).port;
  });

  afterEach(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it("is true when the server answers on the host from OLLAMA_HOST", async () => {
    expect(await ollamaIsUp({ OLLAMA_HOST: `127.0.0.1:${port}` })).toBe(true);
  });

  it("treats 0.0.0.0 as the loopback address", async () => {
    expect(await ollamaIsUp({ OLLAMA_HOST: `0.0.0.0:${port}` })).toBe(true);
  });

  it("is false when nothing listens on that port", async () => {
    const closedPort = port;
    await new Promise<void>((resolve) => server.close(() => resolve()));
    expect(await ollamaIsUp({ OLLAMA_HOST: `127.0.0.1:${closedPort}` })).toBe(false);
  });
});

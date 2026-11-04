import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ServerIdentity } from "./server-identity";

function serve(body: unknown) {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify(body)));
}

describe("ServerIdentity", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("names the server URL, its state, its build and the preset file it reads", async () => {
    serve({ state: "up", url: "http://127.0.0.1:11435", build: "b11429-d81235049" });
    render(<ServerIdentity />);

    expect(await screen.findByText("http://127.0.0.1:11435")).toBeTruthy();
    expect(screen.getByText("up")).toBeTruthy();
    expect(screen.getByText("b11429-d81235049")).toBeTruthy();
    expect(screen.getByText("~/.claude-ollama/presets/models.ini")).toBeTruthy();
    expect(vi.mocked(fetch)).toHaveBeenCalledWith("/api/server/ping", { cache: "no-store" });
  });

  it("says the build is unknown while the server is down", async () => {
    serve({ state: "down", url: "http://127.0.0.1:11435", build: null });
    render(<ServerIdentity />);

    expect(await screen.findByText("down")).toBeTruthy();
    expect(screen.getByText("unknown")).toBeTruthy();
  });
});

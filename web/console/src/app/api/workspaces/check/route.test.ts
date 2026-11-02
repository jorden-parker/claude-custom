import { describe, expect, it, vi } from "vitest";
import { POST } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const checkWorkspaceSkills = vi.hoisted(() => vi.fn());
vi.mock("@/lib/skill-check", () => ({ checkWorkspaceSkills }));

const ORIGIN = "http://127.0.0.1:8808";

const jsonRequest = (body: unknown, contentType = "application/json") =>
  new Request(`${ORIGIN}/api/workspaces/check`, {
    method: "POST",
    headers: { "content-type": contentType, origin: ORIGIN },
    body: JSON.stringify(body),
  });

describe("/api/workspaces/check", () => {
  it("answers the check for a recorded folder", async () => {
    const check = {
      version: "2.1.316 (Claude Code)",
      discovered: ["deploy"],
      missing: [],
      error: null,
    };
    checkWorkspaceSkills.mockResolvedValueOnce({ ok: true, check });

    const response = await POST(
      jsonRequest({ path: "/real/app", size: "27b" }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(check);
    expect(checkWorkspaceSkills).toHaveBeenCalledWith("/real/app", "27b");
  });

  it("passes the refusal through as 400", async () => {
    checkWorkspaceSkills.mockResolvedValueOnce({
      ok: false,
      message: "/gone is not a recorded folder on this machine",
    });

    const response = await POST(jsonRequest({ path: "/gone" }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      message: "/gone is not a recorded folder on this machine",
    });
  });

  it("rejects a body without a path", async () => {
    const response = await POST(jsonRequest({ size: "27b" }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      message: "Expected { path: string, size?: string }",
    });
  });

  it("rejects a body that is not JSON", async () => {
    const response = await POST(
      jsonRequest({ path: "/real/app" }, "text/plain"),
    );

    expect(response.status).toBe(415);
  });
});

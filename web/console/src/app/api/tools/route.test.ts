import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { runOnce } from "@/lib/run-once";
import { GET } from "./route";

vi.mock("@/lib/run-once", () => ({ runOnce: vi.fn() }));
vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const REPORT = { path: "/home/owner/.claude/settings.json", tools: [] };

describe("/api/tools", () => {
  beforeEach(() => {
    process.env.CLAUDE_CUSTOM_HOME = "/repo";
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    vi.unstubAllEnvs();
    vi.mocked(runOnce).mockReset();
  });

  it("returns the report that claude-tools -json prints for the user scope", async () => {
    vi.mocked(runOnce).mockResolvedValue({ code: 0, stdout: JSON.stringify(REPORT), stderr: "" });

    const response = await GET();

    expect(runOnce).toHaveBeenCalledWith(["/repo/bin/claude-tools", "-json", "user"], expect.any(Object));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(REPORT);
  });

  it("answers 502 with the stderr message when claude-tools fails", async () => {
    vi.mocked(runOnce).mockResolvedValue({
      code: 1,
      stdout: "",
      stderr: "claude-tools: no tool catalog yet; open claude-tools once and sync\n",
    });

    const response = await GET();

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      message: "claude-tools: no tool catalog yet; open claude-tools once and sync",
    });
  });

  it("answers 502 when the output is not JSON", async () => {
    vi.mocked(runOnce).mockResolvedValue({ code: 0, stdout: "not json", stderr: "" });

    const response = await GET();

    expect(response.status).toBe(502);
  });
});

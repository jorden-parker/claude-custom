import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GET } from "./route";

describe("GET /api/telemetry", () => {
  beforeEach(() => {
    delete process.env.CLAUDE_TOOL_TELEMETRY;
  });

  afterEach(() => {
    delete process.env.CLAUDE_TOOL_TELEMETRY;
  });

  it("reports telemetry as not configured when the server has no log", async () => {
    const response = await GET();
    expect(await response.json()).toEqual({ configured: false });
  });
});

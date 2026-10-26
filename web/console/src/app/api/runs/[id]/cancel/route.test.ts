import { describe, expect, it } from "vitest";
import { POST } from "./route";

describe("POST /api/runs/[id]/cancel", () => {
  it("answers 404 for an id that is not a run", async () => {
    const response = await POST(new Request("http://127.0.0.1/x", { method: "POST" }), {
      params: Promise.resolve({ id: "../../etc" }),
    });
    expect(response.status).toBe(404);
  });
});

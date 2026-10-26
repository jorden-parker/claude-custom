import { afterEach, describe, expect, it, vi } from "vitest";
import { postRun } from "./post-run";

function stubFetch(status: number, body: unknown) {
  vi.stubGlobal("fetch", vi.fn(async () => Response.json(body, { status })));
}

describe("postRun", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns the run id when the console starts the run", async () => {
    stubFetch(201, { id: "20261026-100000-prune-abcd" });

    expect(await postRun("prune", { names: "a" })).toEqual({ ok: true, id: "20261026-100000-prune-abcd" });
  });

  it("returns the console's reason when the run does not start", async () => {
    stubFetch(409, { message: "A run is already going" });

    expect(await postRun("prune", { names: "a" })).toEqual({ ok: false, message: "A run is already going" });
  });
});

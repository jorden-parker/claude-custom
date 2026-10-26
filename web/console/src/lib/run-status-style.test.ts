import { describe, expect, it } from "vitest";
import { runStatusDotClass, runStatusLabel, runStatusTextClass } from "./run-status-style";

describe("run status style", () => {
  it("names each run status", () => {
    expect(runStatusLabel("ok")).toBe("done");
    expect(runStatusLabel("lost")).toBe("lost");
  });

  it("pulses the dot of a running run", () => {
    expect(runStatusDotClass("running")).toContain("animate-pulse");
    expect(runStatusDotClass("ok")).not.toContain("animate-pulse");
  });

  it("colors a failed run red", () => {
    expect(runStatusTextClass("failed")).toContain("text-red-700");
  });
});

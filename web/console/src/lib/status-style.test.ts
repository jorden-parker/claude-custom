import { describe, expect, it } from "vitest";
import { headerStatusLabel, statusDotClass, statusTextClass } from "./status-style";

describe("statusTextClass", () => {
  it("colors the status text green for done and red for failed", () => {
    expect(statusTextClass("ok")).toContain("text-success-foreground");
    expect(statusTextClass("error")).toContain("text-error-foreground");
  });
});

describe("headerStatusLabel", () => {
  it("names each review status", () => {
    expect(headerStatusLabel("ok")).toBe("done");
    expect(headerStatusLabel("error")).toBe("failed");
    expect(headerStatusLabel("running")).toBe("running");
    expect(headerStatusLabel("stopped")).toBe("stopped");
  });
});

describe("statusDotClass", () => {
  it("colors done green, failed red, running blue and stopped grey", () => {
    expect(statusDotClass("ok")).toContain("bg-success-foreground");
    expect(statusDotClass("error")).toContain("bg-error-foreground");
    expect(statusDotClass("running")).toContain("bg-info-foreground");
    expect(statusDotClass("running")).toContain("animate-pulse");
    expect(statusDotClass("stopped")).toContain("bg-muted-foreground");
    expect(statusDotClass("stopped")).not.toContain("animate-pulse");
  });
});

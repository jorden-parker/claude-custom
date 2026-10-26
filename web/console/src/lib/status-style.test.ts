import { describe, expect, it } from "vitest";
import { headerStatusLabel, statusDotClass, statusTextClass } from "./status-style";

describe("statusTextClass", () => {
  it("colors the status text green for done and red for failed", () => {
    expect(statusTextClass("ok")).toContain("text-green-700");
    expect(statusTextClass("error")).toContain("text-red-700");
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
    expect(statusDotClass("ok")).toContain("bg-green-500");
    expect(statusDotClass("error")).toContain("bg-red-500");
    expect(statusDotClass("running")).toContain("bg-blue-500");
    expect(statusDotClass("running")).toContain("animate-pulse");
    expect(statusDotClass("stopped")).toContain("bg-muted-foreground");
    expect(statusDotClass("stopped")).not.toContain("animate-pulse");
  });
});

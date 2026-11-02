import { describe, expect, it } from "vitest";
import { levelBoxClass, levelTextClass } from "./level-style";

describe("levelTextClass", () => {
  it("colors each level with its status role", () => {
    expect(levelTextClass("ok")).toContain("text-success-foreground");
    expect(levelTextClass("warn")).toContain("text-warning-foreground");
    expect(levelTextClass("fail")).toContain("text-error-foreground");
    expect(levelTextClass("error")).toContain("text-error-foreground");
    expect(levelTextClass("info")).toContain("text-info-foreground");
  });
});

describe("levelBoxClass", () => {
  it("draws each level as a banner with its role border and fill", () => {
    expect(levelBoxClass("warn")).toContain("border-warning-border bg-warning");
    expect(levelBoxClass("fail")).toContain("border-error-border bg-error");
    expect(levelBoxClass("ok")).toContain("border-success-border bg-success");
    expect(levelBoxClass("info")).toContain("border-info-border bg-info");
    expect(levelBoxClass("error")).toContain("border-error-border bg-error");
  });
});

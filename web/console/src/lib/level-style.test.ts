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
  it("gives each level only its role border, fill and text color", () => {
    expect(levelBoxClass("warn")).toBe(
      "border-warning-border bg-warning text-warning-foreground",
    );
    expect(levelBoxClass("fail")).toBe(
      "border-error-border bg-error text-error-foreground",
    );
    expect(levelBoxClass("error")).toBe(
      "border-error-border bg-error text-error-foreground",
    );
    expect(levelBoxClass("ok")).toBe(
      "border-success-border bg-success text-success-foreground",
    );
    expect(levelBoxClass("info")).toBe(
      "border-info-border bg-info text-info-foreground",
    );
  });
});

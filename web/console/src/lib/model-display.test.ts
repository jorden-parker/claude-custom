import { describe, expect, it } from "vitest";
import {
  gigabytes,
  namesToRemove,
  sizeStateOf,
  totalBytes,
  type InstalledModel,
  type SizeStatus,
} from "./model-display";

describe("model display helpers", () => {
  const size = (overrides: Partial<SizeStatus>): SizeStatus => ({
    size: "27b",
    model: "qwen3.8-27b-cc",
    base: "qwen3.8:27b-mlx",
    installed: true,
    class: "profile",
    ...overrides,
  });

  it("tells installed, missing and mismatched sizes apart", () => {
    expect(sizeStateOf(size({}))).toBe("installed");
    expect(sizeStateOf(size({ installed: false, class: null }))).toBe("missing");
    expect(sizeStateOf(size({ class: "mismatch" }))).toBe("mismatch");
  });

  it("lists the names to remove, in order, and their total size", () => {
    const models: InstalledModel[] = [
      { name: "a:latest", class: "orphan", bytes: 1_500_000_000, loaded: false },
      { name: "b/c:7b", class: "third-party", bytes: 2_000_000_000, loaded: true },
    ];

    expect(namesToRemove(models)).toEqual(["a:latest", "b/c:7b"]);
    expect(gigabytes(totalBytes(models))).toBe("3.5");
  });
});

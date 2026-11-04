import { describe, expect, it } from "vitest";
import {
  gigabytes,
  namesToRemove,
  sizeStateOf,
  totalBytes,
  type SizeStatus,
  type WeightFile,
} from "./model-display";

describe("model display helpers", () => {
  const size = (overrides: Partial<SizeStatus>): SizeStatus => ({
    size: "27b",
    model: "qwen3.8-27b-cc",
    file: "Qwen3.8-27B-UD-Q4_K_XL.gguf",
    state: "pinned",
    ...overrides,
  });

  it("tells installed, missing, partial and mismatched sizes apart", () => {
    expect(sizeStateOf(size({}))).toBe("installed");
    expect(sizeStateOf(size({ state: null }))).toBe("missing");
    expect(sizeStateOf(size({ state: "orphan" }))).toBe("missing");
    expect(sizeStateOf(size({ state: "partial" }))).toBe("partial");
    expect(sizeStateOf(size({ state: "mismatch" }))).toBe("mismatch");
  });

  it("lists the names to remove, in order, and their total size", () => {
    const files: WeightFile[] = [
      { name: "Old-Q4_K_M.gguf", state: "orphan", size: null, bytes: 1_500_000_000 },
      { name: "Half.gguf.part", state: "partial", size: "27b", bytes: 2_000_000_000 },
    ];

    expect(namesToRemove(files)).toEqual(["Old-Q4_K_M.gguf", "Half.gguf.part"]);
    expect(gigabytes(totalBytes(files))).toBe("3.5");
  });
});

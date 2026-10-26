import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { baseModelForSize, modelForSize } from "./size-models";

const REPO_DIR = fileURLToPath(new URL("../../../../", import.meta.url));

describe("modelForSize", () => {
  it("reads the model of a configured size", () => {
    expect(modelForSize(REPO_DIR, "35b")).toBe("qwen3.6-35b-cc");
    expect(modelForSize(REPO_DIR, "27b")).toBe("qwen3.8-27b-cc");
  });

  it("gives null for a size that is not configured", () => {
    expect(modelForSize(REPO_DIR, "999b")).toBeNull();
  });

  it("gives null for a size that would leave the ollama folder", () => {
    expect(modelForSize(REPO_DIR, "../ollama/settings.35b")).toBeNull();
    expect(modelForSize(REPO_DIR, "")).toBeNull();
  });
});

describe("baseModelForSize", () => {
  it("reads the FROM line of a configured size's Modelfile", () => {
    expect(baseModelForSize(REPO_DIR, "27b")).toBe("qwen3.8:27b-mlx");
  });

  it("gives null for a size that is not configured", () => {
    expect(baseModelForSize(REPO_DIR, "999b")).toBeNull();
    expect(baseModelForSize(REPO_DIR, "../ollama/Modelfile.27b")).toBeNull();
  });
});

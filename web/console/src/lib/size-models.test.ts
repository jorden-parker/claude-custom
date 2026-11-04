import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { baseModelForSize, modelForSize, sizeSettings } from "./size-models";

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

describe("sizeSettings", () => {
  it("reads a configured size's context and output tokens", () => {
    expect(sizeSettings(REPO_DIR, "27b")).toMatchObject({
      context: 65536,
      outputTokens: 8192,
    });
  });

  it("gives null sizes for a size that is not configured", () => {
    expect(sizeSettings(REPO_DIR, "999b")).toEqual({
      context: null,
      outputTokens: null,
      parameters: {},
    });
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

import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { embeddingPreset, modelForSize, sizeSettings, weightsFileForSize } from "./size-models";

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

describe("weightsFileForSize", () => {
  it("reads the GGUF file of a configured size", () => {
    expect(weightsFileForSize(REPO_DIR, "27b")).toBe("Qwen3.8-27B-UD-Q4_K_XL.gguf");
  });

  it("gives null for a size that is not configured", () => {
    expect(weightsFileForSize(REPO_DIR, "999b")).toBeNull();
    expect(weightsFileForSize(REPO_DIR, "__proto__")).toBeNull();
  });
});

describe("embeddingPreset", () => {
  it("reads the embedding model and its GGUF file", () => {
    expect(embeddingPreset(REPO_DIR)).toEqual({
      model: "qwen3-embedding:0.6b",
      file: "Qwen3-Embedding-0.6B-Q8_0.gguf",
    });
  });

  it("gives null without an embedding file", () => {
    expect(embeddingPreset("/nonexistent")).toBeNull();
  });
});

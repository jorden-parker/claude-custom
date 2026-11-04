import { describe, expect, it } from "vitest";
import { EDITABLE_VARIABLES, validServerValue } from "./server-vars";

describe("EDITABLE_VARIABLES", () => {
  it("leaves the host, origins and models folder read-only", () => {
    for (const name of ["OLLAMA_HOST", "OLLAMA_ORIGINS", "OLLAMA_MODELS"]) {
      expect(EDITABLE_VARIABLES.has(name)).toBe(false);
    }
  });

  it("lists the eight tuning variables", () => {
    expect([...EDITABLE_VARIABLES.keys()].sort()).toEqual([
      "OLLAMA_CONTEXT_LENGTH",
      "OLLAMA_DEBUG",
      "OLLAMA_FLASH_ATTENTION",
      "OLLAMA_KEEP_ALIVE",
      "OLLAMA_KV_CACHE_TYPE",
      "OLLAMA_MAX_LOADED_MODELS",
      "OLLAMA_MAX_QUEUE",
      "OLLAMA_NUM_PARALLEL",
    ]);
  });
});

describe("validServerValue", () => {
  it.each([
    ["OLLAMA_KEEP_ALIVE", "-1"],
    ["OLLAMA_KEEP_ALIVE", "30m"],
    ["OLLAMA_KEEP_ALIVE", "500ms"],
    ["OLLAMA_KEEP_ALIVE", "1h"],
    ["OLLAMA_KEEP_ALIVE", "120"],
    ["OLLAMA_MAX_LOADED_MODELS", "1"],
    ["OLLAMA_MAX_LOADED_MODELS", "16"],
    ["OLLAMA_NUM_PARALLEL", "4"],
    ["OLLAMA_MAX_QUEUE", "100000"],
    ["OLLAMA_CONTEXT_LENGTH", "2048"],
    ["OLLAMA_CONTEXT_LENGTH", "262144"],
    ["OLLAMA_FLASH_ATTENTION", "1"],
    ["OLLAMA_DEBUG", "0"],
    ["OLLAMA_KV_CACHE_TYPE", "f16"],
    ["OLLAMA_KV_CACHE_TYPE", "q8_0"],
    ["OLLAMA_KV_CACHE_TYPE", "q4_0"],
  ])("accepts %s=%s", (name, value) => {
    expect(validServerValue(name, value)).toBe(true);
  });

  it.each([
    ["OLLAMA_KEEP_ALIVE", "30x"],
    ["OLLAMA_KEEP_ALIVE", "1000000h"],
    ["OLLAMA_MAX_LOADED_MODELS", "0"],
    ["OLLAMA_MAX_LOADED_MODELS", "17"],
    ["OLLAMA_NUM_PARALLEL", "2.5"],
    ["OLLAMA_MAX_QUEUE", "100001"],
    ["OLLAMA_CONTEXT_LENGTH", "2047"],
    ["OLLAMA_CONTEXT_LENGTH", "262145"],
    ["OLLAMA_FLASH_ATTENTION", "true"],
    ["OLLAMA_DEBUG", "2"],
    ["OLLAMA_KV_CACHE_TYPE", "q5_0"],
    ["OLLAMA_KV_CACHE_TYPE", ""],
  ])("rejects %s=%s", (name, value) => {
    expect(validServerValue(name, value)).toBe(false);
  });

  it("rejects a value with a comma or an equals sign", () => {
    expect(validServerValue("OLLAMA_KEEP_ALIVE", "1h,OLLAMA_DEBUG=1")).toBe(false);
    expect(validServerValue("OLLAMA_KEEP_ALIVE", "1h=2")).toBe(false);
  });

  it("rejects a variable that is not editable", () => {
    expect(validServerValue("OLLAMA_HOST", "0.0.0.0")).toBe(false);
    expect(validServerValue("OLLAMA_ORIGINS", "*")).toBe(false);
    expect(validServerValue("constructor", "1")).toBe(false);
  });
});

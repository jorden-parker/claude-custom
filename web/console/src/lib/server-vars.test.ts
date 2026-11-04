import { describe, expect, it } from "vitest";
import { SERVER_SETTINGS, serverSetting, validServerValue } from "./server-vars";

describe("SERVER_SETTINGS", () => {
  it("lists the preset keys of the server settings, in order", () => {
    expect(SERVER_SETTINGS.map((setting) => setting.key)).toEqual([
      "models-max",
      "ctx-checkpoints",
      "checkpoint-min-step",
      "cache-ram",
      "cache-type-k",
      "cache-type-v",
      "flash-attn",
      "parallel",
      "batch-size",
      "ubatch-size",
      "cache-reuse",
      "prio",
      "sleep-idle-seconds",
    ]);
  });

  it("gives every setting a label, a help sentence and an input kind", () => {
    for (const setting of SERVER_SETTINGS) {
      expect(setting.label).not.toBe("");
      expect(setting.help).toMatch(/\.$/);
      expect(["number", "choice"]).toContain(setting.input.kind);
    }
  });

  it("takes models-max and ctx-checkpoints as numbers in their ranges", () => {
    expect(serverSetting("models-max")?.input).toEqual({ kind: "number", min: 1, max: 4 });
    expect(serverSetting("ctx-checkpoints")?.input).toEqual({ kind: "number", min: 0, max: 256 });
  });

  it("takes the cache types and flash attention as choices", () => {
    for (const key of ["cache-type-k", "cache-type-v"]) {
      expect(serverSetting(key)?.input).toEqual({ kind: "choice", choices: ["f16", "q8_0", "q4_0"] });
    }
    expect(serverSetting("flash-attn")?.input).toEqual({ kind: "choice", choices: ["on", "off", "auto"] });
  });

  it("knows no other key", () => {
    expect(serverSetting("n-gpu-layers")).toBeUndefined();
    expect(serverSetting("constructor")).toBeUndefined();
  });
});

describe("validServerValue", () => {
  it.each([
    ["models-max", "1"],
    ["models-max", "4"],
    ["ctx-checkpoints", "0"],
    ["ctx-checkpoints", "256"],
    ["cache-type-k", "q8_0"],
    ["cache-type-v", "f16"],
    ["flash-attn", "auto"],
    ["sleep-idle-seconds", "-1"],
    ["prio", "2"],
  ])("accepts %s=%s", (name, value) => {
    expect(validServerValue(name, value)).toBe(true);
  });

  it.each([
    ["models-max", "0"],
    ["models-max", "5"],
    ["models-max", "2.5"],
    ["models-max", ""],
    ["ctx-checkpoints", "257"],
    ["ctx-checkpoints", "-1"],
    ["cache-type-k", "q5_0"],
    ["flash-attn", "1"],
    ["sleep-idle-seconds", "-2"],
    ["prio", "-01"],
  ])("rejects %s=%s", (name, value) => {
    expect(validServerValue(name, value)).toBe(false);
  });

  it("rejects a value with a comma or an equals sign", () => {
    expect(validServerValue("models-max", "2,parallel=4")).toBe(false);
    expect(validServerValue("flash-attn", "on=2")).toBe(false);
  });

  it("rejects a key that is not a setting", () => {
    expect(validServerValue("n-gpu-layers", "99")).toBe(false);
    expect(validServerValue("constructor", "1")).toBe(false);
  });
});

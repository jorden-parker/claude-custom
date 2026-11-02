import fs from "node:fs";
import { describe, expect, it } from "vitest";
import {
  DEFAULT_PRESET_ID,
  MOCK_PRESETS,
  presetIds,
  presetOrDefault,
} from "./presets.ts";

const globals = fs.readFileSync(
  new URL("../../app/globals.css", import.meta.url),
  "utf8",
);

describe("mock presets", () => {
  it("have unique ids and a prompt paragraph each", () => {
    expect(new Set(presetIds()).size).toBe(MOCK_PRESETS.length);
    for (const preset of MOCK_PRESETS) {
      expect(preset.prompt.length).toBeGreaterThan(40);
      expect(preset.name).not.toBe("");
    }
  });

  it("fall back to the default preset for an unknown id", () => {
    expect(presetOrDefault("nope").id).toBe(DEFAULT_PRESET_ID);
    expect(presetOrDefault(undefined).id).toBe(DEFAULT_PRESET_ID);
    expect(presetOrDefault("brutalist").id).toBe("brutalist");
  });

  it("each have a palette block in globals.css with every --mock token", () => {
    const tokens = [
      "bg",
      "surface",
      "surface-2",
      "line",
      "ink",
      "ink-soft",
      "ink-faint",
      "accent",
      "on-accent",
      "success",
      "success-bg",
      "warning",
      "warning-bg",
      "radius",
      "font",
    ];
    for (const id of presetIds()) {
      const block = globals.match(
        new RegExp(`\\.mock-frame\\[data-preset="${id}"\\] \\{([^}]*)\\}`),
      );
      expect(block, id).not.toBeNull();
      for (const token of tokens) {
        expect(block?.[1], `${id} ${token}`).toContain(`--mock-${token}:`);
      }
    }
  });
});

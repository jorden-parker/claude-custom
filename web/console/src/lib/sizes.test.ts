import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { configuredSizes } from "./sizes";

describe("configuredSizes", () => {
  let repo: string;
  let profileDir: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "sizes-"));
    profileDir = path.join(repo, "ollama");
    fs.mkdirSync(profileDir);
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  function touch(name: string) {
    fs.writeFileSync(path.join(profileDir, name), "");
  }

  function writeSizes(sizes: string[]) {
    fs.writeFileSync(path.join(profileDir, "sizes.json"), JSON.stringify(Object.fromEntries(sizes.map((size) => [size, {}]))));
  }

  it("lists sorted sizes that have a settings file and a sizes.json entry", () => {
    touch("settings.35b.json");
    touch("settings.27b.json");
    writeSizes(["27b", "35b"]);
    expect(configuredSizes(repo)).toEqual(["27b", "35b"]);
  });

  it("leaves out a size missing either the settings file or its entry", () => {
    touch("settings.27b.json");
    touch("settings.9b.json");
    writeSizes(["27b", "4b"]);
    expect(configuredSizes(repo)).toEqual(["27b"]);
  });

  it("lists nothing when sizes.json is missing or unreadable", () => {
    touch("settings.27b.json");
    expect(configuredSizes(repo)).toEqual([]);
    touch("sizes.json");
    expect(configuredSizes(repo)).toEqual([]);
  });

  it("never needs a Modelfile", () => {
    touch("settings.27b.json");
    writeSizes(["27b"]);
    expect(fs.existsSync(path.join(profileDir, "Modelfile.27b"))).toBe(false);
    expect(configuredSizes(repo)).toEqual(["27b"]);
  });

  it("returns an empty list when the folder or the repo is missing", () => {
    expect(configuredSizes(path.join(repo, "absent"))).toEqual([]);
    expect(configuredSizes("")).toEqual([]);
  });
});

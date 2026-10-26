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

  it("lists sorted sizes that have both a settings file and a Modelfile", () => {
    touch("settings.35b.json");
    touch("Modelfile.35b");
    touch("settings.27b.json");
    touch("Modelfile.27b");
    expect(configuredSizes(repo)).toEqual(["27b", "35b"]);
  });

  it("leaves out a size missing either file", () => {
    touch("settings.27b.json");
    touch("Modelfile.27b");
    touch("settings.9b.json");
    touch("Modelfile.4b");
    expect(configuredSizes(repo)).toEqual(["27b"]);
  });

  it("returns an empty list when the folder or the repo is missing", () => {
    expect(configuredSizes(path.join(repo, "absent"))).toEqual([]);
    expect(configuredSizes("")).toEqual([]);
  });
});

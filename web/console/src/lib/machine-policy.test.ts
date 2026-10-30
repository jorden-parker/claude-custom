import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  machineConfigDir,
  policyPath,
  readPolicyText,
  sandboxOffState,
  writePolicyText,
} from "./machine-policy";

describe("machine policy files", () => {
  let configHome: string;
  let previousConfigHome: string | undefined;

  beforeEach(() => {
    configHome = fs.mkdtempSync(path.join(os.tmpdir(), "machine-policy-"));
    previousConfigHome = process.env.XDG_CONFIG_HOME;
    process.env.XDG_CONFIG_HOME = configHome;
  });

  afterEach(() => {
    if (previousConfigHome === undefined) {
      delete process.env.XDG_CONFIG_HOME;
    } else {
      process.env.XDG_CONFIG_HOME = previousConfigHome;
    }
    fs.rmSync(configHome, { recursive: true, force: true });
  });

  it("keeps the files under XDG_CONFIG_HOME/claude-custom", () => {
    expect(machineConfigDir()).toBe(path.join(configHome, "claude-custom"));
    expect(policyPath("gh-repos")).toBe(
      path.join(configHome, "claude-custom", "gh-repos"),
    );
  });

  it("reads null for a file that does not exist", () => {
    expect(readPolicyText("command-rules")).toBeNull();
  });

  it("round trips the text and writes the file 0600 in a 0700 folder", () => {
    writePolicyText("gh-repos", "acme/web\n");

    expect(readPolicyText("gh-repos")).toBe("acme/web\n");
    expect(fs.statSync(policyPath("gh-repos")).mode & 0o777).toBe(0o600);
    expect(fs.statSync(machineConfigDir()).mode & 0o777).toBe(0o700);
  });

  it("replaces the text of an existing file", () => {
    writePolicyText("enabled-tools", "Artifact\n");
    writePolicyText("enabled-tools", "Workflow\n");

    expect(readPolicyText("enabled-tools")).toBe("Workflow\n");
  });

  it("refuses to write through a symlink and leaves the target alone", () => {
    const target = path.join(configHome, "elsewhere");
    fs.writeFileSync(target, "keep\n");
    fs.mkdirSync(machineConfigDir(), { recursive: true });
    fs.symlinkSync(target, policyPath("gh-repos"));

    expect(() => writePolicyText("gh-repos", "acme/web\n")).toThrow(
      "it is a symlink",
    );
    expect(fs.readFileSync(target, "utf8")).toBe("keep\n");
  });

  it("reports sandbox-off by its existence only", () => {
    const sandboxOff = path.join(configHome, "claude-custom", "sandbox-off");
    expect(sandboxOffState()).toEqual({ exists: false, path: sandboxOff });

    fs.mkdirSync(machineConfigDir(), { recursive: true });
    fs.writeFileSync(sandboxOff, "");

    expect(sandboxOffState()).toEqual({ exists: true, path: sandboxOff });
  });
});

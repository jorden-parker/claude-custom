import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { consoleRepoDir } from "./sizes";
import type { PolicyFile } from "./machine-policy-rules";

const FILE_MODE = 0o600;
const FOLDER_MODE = 0o700;
const SANDBOX_OFF_NAME = "sandbox-off";
const OVERLAY_PATH = ["personal", "settings.tokens.json"];

export function machineConfigDir(): string {
  const configHome = process.env.XDG_CONFIG_HOME;
  const base = configHome ? configHome : path.join(os.homedir(), ".config");
  return path.join(base, "claude-custom");
}

export function policyPath(file: PolicyFile): string {
  return path.join(machineConfigDir(), file);
}

export function policyProblem(file: PolicyFile): string | null {
  const target = policyPath(file);
  return isSymlink(target)
    ? `${target} is a symlink; edit the file it points to instead`
    : null;
}

export function readPolicyText(file: PolicyFile): string | null {
  try {
    return fs.readFileSync(policyPath(file), "utf8");
  } catch {
    return null;
  }
}

export function writePolicyText(file: PolicyFile, text: string): void {
  const target = policyPath(file);
  const problem = policyProblem(file);
  if (problem !== null) {
    throw new Error(problem);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true, mode: FOLDER_MODE });
  const temporary = `${target}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temporary, text, { mode: FILE_MODE });
  fs.renameSync(temporary, target);
}

export function sandboxOffState(): { exists: boolean; path: string } {
  const target = path.join(machineConfigDir(), SANDBOX_OFF_NAME);
  return { exists: fs.existsSync(target), path: target };
}

export function overlayDenyRules(): string[] {
  const repoDir = consoleRepoDir();
  if (repoDir === "") {
    return [];
  }
  try {
    const overlay = JSON.parse(
      fs.readFileSync(path.join(repoDir, ...OVERLAY_PATH), "utf8"),
    ) as { permissions?: { deny?: unknown } };
    const deny = overlay.permissions?.deny;
    return Array.isArray(deny)
      ? deny.filter((rule): rule is string => typeof rule === "string")
      : [];
  } catch {
    return [];
  }
}

function isSymlink(target: string): boolean {
  try {
    return fs.lstatSync(target).isSymbolicLink();
  } catch {
    return false;
  }
}

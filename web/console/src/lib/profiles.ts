import fs from "node:fs";
import path from "node:path";
import { recordChange } from "./history";
import {
  isSymlink,
  machineConfigDir,
  readTextOrNull as readText,
  writePrivateText,
} from "./machine-policy";
import { overrideCount, type ProfileKind, type ProfileOverride } from "./profile-rules";
import { modelForSize, sizeSettings } from "./size-models";
import { consoleRepoDir, listSizes } from "./sizes";

export type ProfileSummary = {
  id: string;
  title: string;
  kind: ProfileKind;
  model: string | null;
  context: number | null;
  overrides: number;
};

const CLAUDE_CODE_PROFILE = "claude-code";
const OLLAMA_PREFIX = "ollama-";
const HISTORY_KIND = "profile";
const EMPTY_TEXT = "{}\n";

export function profileIds(): string[] {
  return [CLAUDE_CODE_PROFILE, ...listSizes().map((size) => `${OLLAMA_PREFIX}${size}`)];
}

export function isKnownProfile(id: string): boolean {
  return profileIds().includes(id);
}

export function profileKind(id: string): ProfileKind {
  return id === CLAUDE_CODE_PROFILE ? "claude-code" : "ollama";
}

export function sizeOfProfile(id: string): string | null {
  return id.startsWith(OLLAMA_PREFIX) ? id.slice(OLLAMA_PREFIX.length) : null;
}

function profileTitle(id: string): string {
  const size = sizeOfProfile(id);
  return size === null ? "Claude Code" : `Ollama ${size}`;
}

export function listProfiles(): ProfileSummary[] {
  return profileIds().map((id) => profileSummary(id));
}

export function profileSummary(id: string): ProfileSummary {
  const size = sizeOfProfile(id);
  const repoDir = consoleRepoDir();
  return {
    id,
    title: profileTitle(id),
    kind: profileKind(id),
    model: size === null ? null : modelForSize(repoDir, size),
    context: size === null ? null : sizeSettings(repoDir, size).context,
    overrides: overrideCount(readOverride(id)),
  };
}

function profilesDir(): string {
  return path.join(machineConfigDir(), "profiles");
}

export function profileFilePath(id: string): string {
  return path.join(profilesDir(), `${id}.json`);
}

export function profileProblem(id: string): string | null {
  const target = profileFilePath(id);
  if (isSymlink(profilesDir())) {
    return `${profilesDir()} is a symlink; edit the folder it points to instead`;
  }
  return isSymlink(target) ? `${target} is a symlink; edit the file it points to instead` : null;
}

export function readOverride(id: string): ProfileOverride {
  if (profileProblem(id) !== null) {
    return {};
  }
  const text = readText(profileFilePath(id));
  const parsed = text === null ? null : parseJson(text);
  return isObject(parsed) ? (parsed as ProfileOverride) : {};
}

export function saveOverride(id: string, override: ProfileOverride): void {
  const problem = profileProblem(id);
  if (problem !== null) {
    throw new Error(problem);
  }
  const target = profileFilePath(id);
  const before = readText(target);
  const next = overrideCount(override) === 0 ? null : `${JSON.stringify(override, null, 2)}\n`;
  if (before === null && next === null) {
    return;
  }
  writeOrRemove(target, next);
  recordChange({
    kind: HISTORY_KIND,
    path: target,
    before,
    after: next ?? EMPTY_TEXT,
    source: "console",
  });
}

function writeOrRemove(target: string, text: string | null): void {
  if (text === null) {
    fs.rmSync(target, { force: true });
    return;
  }
  writePrivateText(target, text);
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function isObject(value: unknown): boolean {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}


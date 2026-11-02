import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { recordChange } from "./history";
import { isSymlink, readTextOrNull, writePrivateText } from "./machine-policy";

export type ProjectSkill = {
  name: string;
  description: string | null;
  modelInvocable: boolean;
};

export type Workspace = {
  path: string;
  trusted: boolean;
  exists: boolean;
  skills: ProjectSkill[];
};

export type WorkspaceState = {
  path: string;
  workspaces: Workspace[];
};

export type TrustResult =
  { ok: true; state: WorkspaceState } | { ok: false; message: string };

type ProjectRecord = Record<string, unknown>;
type SessionState = Record<string, unknown> & {
  projects?: Record<string, ProjectRecord>;
};

const SESSION_DIR_NAME = ".claude-ollama";
const STATE_FILE_NAME = ".claude.json";
const SKILLS_DIR = path.join(".claude", "skills");
const SKILL_FILE = "SKILL.md";
const TRUST_KEY = "hasTrustDialogAccepted";
const HISTORY_KIND = "workspace-trust";
const FRONTMATTER_FENCE = "---";

function sessionStatePath(): string {
  return path.join(os.homedir(), SESSION_DIR_NAME, STATE_FILE_NAME);
}

export function readWorkspaces(): WorkspaceState {
  const projects = readSessionState().projects ?? {};
  const workspaces = Object.entries(projects)
    .map(([folder, record]) => describeWorkspace(folder, record))
    .sort((a, b) => a.path.localeCompare(b.path));
  return { path: sessionStatePath(), workspaces };
}

export function setWorkspaceTrust(
  folder: string,
  trusted: boolean,
): TrustResult {
  const key = workspaceKey(folder);
  if (!key.ok) {
    return key;
  }
  if (isSymlink(sessionStatePath())) {
    return {
      ok: false,
      message: `${sessionStatePath()} is a symlink; edit the file it points to instead`,
    };
  }
  const before = readTextOrNull(sessionStatePath());
  const state = readSessionState();
  const projects = state.projects ?? {};
  projects[key.key] = { ...(projects[key.key] ?? {}), [TRUST_KEY]: trusted };
  const after = `${JSON.stringify({ ...state, projects }, null, 2)}\n`;
  writePrivateText(sessionStatePath(), after);
  recordChange({
    kind: HISTORY_KIND,
    path: sessionStatePath(),
    before,
    after,
    source: "console",
  });
  return { ok: true, state: readWorkspaces() };
}

export function projectSkills(folder: string): ProjectSkill[] {
  const skillsDir = path.join(folder, SKILLS_DIR);
  return listFolders(skillsDir)
    .map((name) => readSkill(name, path.join(skillsDir, name, SKILL_FILE)))
    .filter((skill): skill is ProjectSkill => skill !== null)
    .sort((a, b) => a.name.localeCompare(b.name));
}

type KeyResult = { ok: true; key: string } | { ok: false; message: string };

function workspaceKey(folder: string): KeyResult {
  if (!path.isAbsolute(folder)) {
    return { ok: false, message: "Expected an absolute folder path" };
  }
  const existing = Object.keys(readSessionState().projects ?? {});
  if (existing.includes(folder)) {
    return { ok: true, key: folder };
  }
  if (!isDirectory(folder)) {
    return { ok: false, message: `${folder} is not a folder on this machine` };
  }
  return { ok: true, key: fs.realpathSync(folder) };
}

function describeWorkspace(folder: string, record: ProjectRecord): Workspace {
  const exists = isDirectory(folder);
  return {
    path: folder,
    trusted: record[TRUST_KEY] === true,
    exists,
    skills: exists ? projectSkills(folder) : [],
  };
}

function readSessionState(): SessionState {
  const text = readTextOrNull(sessionStatePath());
  if (text === null) {
    return {};
  }
  try {
    const parsed: unknown = JSON.parse(text);
    return isRecord(parsed) ? (parsed as SessionState) : {};
  } catch {
    return {};
  }
}

function readSkill(folderName: string, file: string): ProjectSkill | null {
  const text = readTextOrNull(file);
  if (text === null) {
    return null;
  }
  const frontmatter = parseFrontmatter(text);
  return {
    name: frontmatter.name ?? folderName,
    description: frontmatter.description ?? null,
    modelInvocable: frontmatter["disable-model-invocation"] !== "true",
  };
}

export function parseFrontmatter(text: string): Record<string, string> {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== FRONTMATTER_FENCE) {
    return {};
  }
  const fields: Record<string, string> = {};
  for (const line of lines.slice(1)) {
    if (line === FRONTMATTER_FENCE) {
      return fields;
    }
    const separator = line.indexOf(":");
    if (separator > 0) {
      fields[line.slice(0, separator).trim()] = line
        .slice(separator + 1)
        .trim();
    }
  }
  return fields;
}

function listFolders(dir: string): string[] {
  try {
    return fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() || entry.isSymbolicLink())
      .map((entry) => entry.name);
  } catch {
    return [];
  }
}

function isDirectory(target: string): boolean {
  try {
    return fs.statSync(target).isDirectory();
  } catch {
    return false;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

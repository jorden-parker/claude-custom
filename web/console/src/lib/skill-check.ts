import path from "node:path";
import { runOnce } from "./run-once";
import { consoleRepoDir, listSizes } from "./sizes";
import { projectSkills, readWorkspaces } from "./workspaces";

export type SkillCheck = {
  version: string | null;
  discovered: string[];
  missing: string[];
  error: string | null;
};

export type SkillCheckResult =
  { ok: true; check: SkillCheck } | { ok: false; message: string };

type ScriptReport = {
  claude_version?: unknown;
  skills?: unknown;
  error?: unknown;
};

const SCRIPT = path.join("bin", "skill-check");
const RUN_OPTIONS = { timeoutMs: 150_000, maxBytes: 1024 * 1024 };

export async function checkWorkspaceSkills(
  folder: string,
  size: string | undefined,
): Promise<SkillCheckResult> {
  const workspace = readWorkspaces().workspaces.find(
    (candidate) => candidate.path === folder,
  );
  if (workspace === undefined || !workspace.exists) {
    return {
      ok: false,
      message: `${folder} is not a recorded folder on this machine`,
    };
  }
  const chosenSize = size ?? listSizes()[0];
  if (chosenSize === undefined || !listSizes().includes(chosenSize)) {
    return { ok: false, message: `Unknown size ${size ?? ""}`.trim() };
  }
  const result = await runOnce(
    [path.join(consoleRepoDir(), SCRIPT), "--size", chosenSize, folder],
    RUN_OPTIONS,
  );
  const report = parseReport(result.stdout);
  if (report === null) {
    return {
      ok: false,
      message: `skill-check failed (exit ${result.code}): ${result.stderr.trim()}`,
    };
  }
  return {
    ok: true,
    check: compare(
      report,
      projectSkills(folder).map((skill) => skill.name),
    ),
  };
}

function compare(report: ScriptReport, expected: string[]): SkillCheck {
  const discovered = Array.isArray(report.skills)
    ? report.skills.filter(isString)
    : [];
  return {
    version: isString(report.claude_version) ? report.claude_version : null,
    discovered,
    missing: Array.isArray(report.skills)
      ? expected.filter((name) => !discovered.includes(name))
      : [],
    error: isString(report.error) ? report.error : null,
  };
}

function parseReport(stdout: string): ScriptReport | null {
  try {
    const parsed: unknown = JSON.parse(stdout);
    return typeof parsed === "object" && parsed !== null
      ? (parsed as ScriptReport)
      : null;
  } catch {
    return null;
  }
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

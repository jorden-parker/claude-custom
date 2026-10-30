import { connection, NextResponse } from "next/server";
import { fetchDomainsPath, readDomains } from "@/lib/fetch-domains";
import { recordChange } from "@/lib/history";
import {
  machineConfigDir,
  overlayDenyRules,
  policyPath,
  policyProblem,
  readPolicyText,
  sandboxOffState,
  writePolicyText,
} from "@/lib/machine-policy";
import {
  POLICY_FILES,
  bareToolNames,
  isPolicyFile,
  parseLines,
  planLines,
  type LinePlan,
  type PolicyFile,
} from "@/lib/machine-policy-rules";

const JSON_CONTENT_TYPE = "application/json";
const HISTORY_KIND_PREFIX = "machine-";
const CONSOLE_SOURCE = "console";
const FETCH_DOMAINS_EDITOR = "/fetch-domains";

type PolicyRequest = { file: string; lines: string[] };
type PlanRequest =
  { ok: true; plan: LinePlan } | { ok: false; message: string };

export async function GET() {
  await connection();
  return NextResponse.json(machineState());
}

export async function PUT(request: Request) {
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return failure("Expected application/json", 415);
  }
  const requested = await readRequest(request);
  if (requested === null) {
    return failure("Expected { file, lines: string[] }", 400);
  }
  return savePolicy(requested);
}

function machineState() {
  const knownTools = knownToolNames();
  return {
    dir: machineConfigDir(),
    files: {
      "gh-repos": policyFileState("gh-repos", knownTools),
      "command-rules": policyFileState("command-rules", knownTools),
      "enabled-tools": policyFileState("enabled-tools", knownTools),
      "fetch-domains": fetchDomainsState(),
    },
    sandboxOff: sandboxOffState(),
    knownTools,
  };
}

function policyFileState(file: PolicyFile, knownTools: string[]) {
  const text = readPolicyText(file);
  return {
    path: policyPath(file),
    text,
    ...parseLines(file, text ?? "", knownTools),
  };
}

function fetchDomainsState() {
  return {
    path: fetchDomainsPath(),
    count: readDomains().hosts.length,
    editor: FETCH_DOMAINS_EDITOR,
  };
}

function savePolicy({ file, lines }: PolicyRequest) {
  if (!isPolicyFile(file)) {
    return failure(
      `Expected file to be one of ${POLICY_FILES.join(", ")}`,
      400,
    );
  }
  const plan = planRequest(file, lines);
  if (!plan.ok) {
    return failure(plan.message, 400);
  }
  const problem = policyProblem(file);
  if (problem !== null) {
    return failure(problem, 409);
  }
  recordChange({
    kind: `${HISTORY_KIND_PREFIX}${file}`,
    path: policyPath(file),
    before: readPolicyText(file),
    after: plan.plan.text,
    source: CONSOLE_SOURCE,
  });
  writePolicyText(file, plan.plan.text);
  return NextResponse.json(machineState());
}

function planRequest(file: PolicyFile, lines: string[]): PlanRequest {
  try {
    return { ok: true, plan: planLines(file, lines, knownToolNames()) };
  } catch (error) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : "not a policy line",
    };
  }
}

function knownToolNames(): string[] {
  return bareToolNames(overlayDenyRules());
}

async function readRequest(request: Request): Promise<PolicyRequest | null> {
  try {
    return requestFrom(await request.json());
  } catch {
    return null;
  }
}

function requestFrom(body: unknown): PolicyRequest | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const { file, lines } = body as { file?: unknown; lines?: unknown };
  const isLineList =
    Array.isArray(lines) && lines.every((line) => typeof line === "string");
  if (typeof file !== "string" || !isLineList) {
    return null;
  }
  return { file, lines };
}

function failure(message: string, status = 400) {
  return NextResponse.json({ message }, { status });
}

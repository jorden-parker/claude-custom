import { connection, NextResponse } from "next/server";
import { recordChange } from "@/lib/history";
import {
  MAX_FETCH_HOSTS,
  SUGGESTED_HOSTS,
  fetchDomainsPath,
  planDomains,
  readDomains,
  type DomainPlan,
  readDomainsText,
  writeDomainsText,
} from "@/lib/fetch-domains";

const JSON_CONTENT_TYPE = "application/json";
const HISTORY_KIND = "fetch-domains";
const CONSOLE_SOURCE = "console";

export async function GET() {
  await connection();
  return NextResponse.json(domainState());
}

export async function PUT(request: Request) {
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return NextResponse.json({ message: "Expected application/json" }, { status: 415 });
  }
  const requested = await readRequestedHosts(request);
  if (requested === null) {
    return NextResponse.json({ message: "Expected { hosts: string[] }" }, { status: 400 });
  }
  if (requested.length > MAX_FETCH_HOSTS) {
    return NextResponse.json({ message: `At most ${MAX_FETCH_HOSTS} hosts` }, { status: 400 });
  }
  const plan = planRequest(requested);
  if (!plan.ok) {
    return NextResponse.json({ message: plan.message }, { status: 400 });
  }
  recordChange({
    kind: HISTORY_KIND,
    path: fetchDomainsPath(),
    before: readDomainsText(),
    after: plan.plan.text,
    source: CONSOLE_SOURCE,
  });
  writeDomainsText(plan.plan.text);
  return NextResponse.json(domainState());
}

function domainState() {
  return { path: fetchDomainsPath(), ...readDomains(), suggested: SUGGESTED_HOSTS };
}

async function readRequestedHosts(request: Request): Promise<string[] | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }
  const hosts = (body as { hosts?: unknown } | null)?.hosts;
  if (!Array.isArray(hosts) || !hosts.every((host) => typeof host === "string")) {
    return null;
  }
  return hosts;
}

type PlanRequest = { ok: true; plan: DomainPlan } | { ok: false; message: string };

function planRequest(hosts: string[]): PlanRequest {
  try {
    return { ok: true, plan: planDomains(hosts) };
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "not a hostname" };
  }
}

import { NextResponse } from "next/server";
import { loadResidency, promoteSession } from "@/lib/lease";
import { PROMOTABLE_RUNGS } from "@/lib/residency";
import { consoleRepoDir } from "@/lib/sizes";

const JSON_CONTENT_TYPE = "application/json";
const RUNG_MESSAGE = `Expected { rung: ${PROMOTABLE_RUNGS.join(" | ")} }`;

type PromotableRung = (typeof PROMOTABLE_RUNGS)[number];

export async function POST(request: Request) {
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return failure("Expected application/json", 415);
  }
  const rung = await readRung(request);
  if (rung === null) {
    return failure(RUNG_MESSAGE, 400);
  }
  const repoDir = consoleRepoDir();
  const loaded = await loadResidency(repoDir);
  if (!loaded.ok) {
    return failure(loaded.message, 502);
  }
  const promoted = await promoteSession(
    repoDir,
    loaded.residency.holders,
    rung,
  );
  if (!promoted.ok) {
    return failure(promoted.message, 409);
  }
  return NextResponse.json(promoted);
}

async function readRung(request: Request): Promise<PromotableRung | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }
  const { rung } = (body as { rung?: unknown } | null) ?? {};
  const known = PROMOTABLE_RUNGS.find((candidate) => candidate === rung);
  return known ?? null;
}

function failure(message: string, status: number) {
  return NextResponse.json({ message }, { status });
}

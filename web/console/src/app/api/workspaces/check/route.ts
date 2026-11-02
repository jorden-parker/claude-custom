import { connection, NextResponse } from "next/server";
import { checkWorkspaceSkills } from "@/lib/skill-check";

const JSON_CONTENT_TYPE = "application/json";

export async function POST(request: Request) {
  await connection();
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return failure("Expected application/json", 415);
  }
  const requested = await readCheckRequest(request);
  if (requested === null) {
    return failure("Expected { path: string, size?: string }", 400);
  }
  const result = await checkWorkspaceSkills(requested.path, requested.size);
  if (!result.ok) {
    return failure(result.message, 400);
  }
  return NextResponse.json(result.check);
}

type CheckRequest = { path: string; size: string | undefined };

async function readCheckRequest(
  request: Request,
): Promise<CheckRequest | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }
  const { path, size } =
    (body as { path?: unknown; size?: unknown } | null) ?? {};
  if (
    typeof path !== "string" ||
    (size !== undefined && typeof size !== "string")
  ) {
    return null;
  }
  return { path, size };
}

function failure(message: string, status: number) {
  return NextResponse.json({ message }, { status });
}

import { connection, NextResponse } from "next/server";
import { readWorkspaces, setWorkspaceTrust } from "@/lib/workspaces";

const JSON_CONTENT_TYPE = "application/json";

export async function GET() {
  await connection();
  return NextResponse.json(readWorkspaces());
}

export async function PUT(request: Request) {
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return failure("Expected application/json", 415);
  }
  const requested = await readTrustRequest(request);
  if (requested === null) {
    return failure("Expected { path: string, trusted: boolean }", 400);
  }
  const result = setWorkspaceTrust(requested.path, requested.trusted);
  if (!result.ok) {
    return failure(result.message, 400);
  }
  return NextResponse.json(result.state);
}

type TrustRequest = { path: string; trusted: boolean };

async function readTrustRequest(
  request: Request,
): Promise<TrustRequest | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }
  const { path, trusted } = (body as Partial<TrustRequest> | null) ?? {};
  if (typeof path !== "string" || typeof trusted !== "boolean") {
    return null;
  }
  return { path, trusted };
}

function failure(message: string, status: number) {
  return NextResponse.json({ message }, { status });
}

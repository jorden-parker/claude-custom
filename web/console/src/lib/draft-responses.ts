import { NextResponse } from "next/server";

const JSON_CONTENT_TYPE = "application/json";

export function isJsonRequest(request: Request): boolean {
  return (
    request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE) ?? false
  );
}

export async function readJsonObject(
  request: Request,
): Promise<Record<string, unknown> | null> {
  try {
    const value: unknown = await request.json();
    return isPlainObject(value) ? value : null;
  } catch {
    return null;
  }
}

export function messageResponse(message: string, status: number) {
  return NextResponse.json({ message }, { status });
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

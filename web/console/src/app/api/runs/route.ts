import { connection, NextResponse } from "next/server";
import { startDeps, startRun } from "@/lib/start-run";
import { listRuns } from "@/lib/run-log";
import type { CommandParams } from "@/lib/console-commands";

const JSON_CONTENT_TYPE = "application/json";

export async function GET() {
  await connection();
  return NextResponse.json(listRuns());
}

export async function POST(request: Request) {
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return NextResponse.json({ message: "Expected application/json" }, { status: 415 });
  }
  const body = await readBody(request);
  if (!body) {
    return NextResponse.json({ message: "Expected a command and params" }, { status: 400 });
  }
  const result = await startRun(body.command, body.params, startDeps());
  if (!result.ok) {
    return NextResponse.json({ message: result.message }, { status: result.status });
  }
  return NextResponse.json({ id: result.id }, { status: 201 });
}

async function readBody(request: Request): Promise<{ command: string; params: CommandParams } | null> {
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    return null;
  }
  if (!isStartBody(value)) {
    return null;
  }
  return value;
}

function isStartBody(value: unknown): value is { command: string; params: CommandParams } {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const { command, params } = value as { command?: unknown; params?: unknown };
  return typeof command === "string" && typeof params === "object" && params !== null && Object.values(params).every((item) => typeof item === "string");
}

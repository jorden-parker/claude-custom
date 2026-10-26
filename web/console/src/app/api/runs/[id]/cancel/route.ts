import { NextResponse } from "next/server";
import { cancelDeps, cancelRun } from "@/lib/start-run";

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(_request: Request, context: RouteContext) {
  const { id } = await context.params;
  const result = cancelRun(id, cancelDeps());
  if (!result.ok) {
    return NextResponse.json({ message: result.message }, { status: result.status });
  }
  return NextResponse.json({ ok: true });
}

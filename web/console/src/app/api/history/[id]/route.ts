import { connection, NextResponse } from "next/server";
import { loadChange } from "@/lib/history";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(_request: Request, context: RouteContext) {
  await connection();
  const { id } = await context.params;
  const change = loadChange(id);
  if (change === null) {
    return NextResponse.json({ message: "no such history entry" }, { status: 404 });
  }
  return NextResponse.json(change);
}

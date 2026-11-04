import { connection, NextResponse } from "next/server";
import { modelServerHealth } from "@/lib/model-server-health";

export async function GET() {
  await connection();
  return NextResponse.json(await modelServerHealth());
}

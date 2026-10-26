import { connection, NextResponse } from "next/server";
import { consoleRepoDir } from "@/lib/sizes";
import { telemetryReport } from "@/lib/telemetry";

export async function GET() {
  await connection();
  return NextResponse.json(await telemetryReport(process.env, consoleRepoDir()));
}

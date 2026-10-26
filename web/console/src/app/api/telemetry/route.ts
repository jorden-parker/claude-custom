import { NextResponse } from "next/server";
import { consoleRepoDir } from "@/lib/sizes";
import { telemetryReport } from "@/lib/telemetry";

export const dynamic = "force-dynamic";

export async function GET() {
  return NextResponse.json(await telemetryReport(process.env, consoleRepoDir()));
}

import { connection, NextResponse } from "next/server";
import { configuredSizes, consoleRepoDir } from "@/lib/sizes";

export async function GET() {
  await connection();
  return NextResponse.json(configuredSizes(consoleRepoDir()));
}

import { connection, NextResponse } from "next/server";
import { listSpeedReports } from "@/lib/speed-reports";

export async function GET() {
  await connection();
  return NextResponse.json(listSpeedReports());
}

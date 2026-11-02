import { connection, NextResponse } from "next/server";
import { latestRescueReport } from "@/lib/rescue-report";

const NO_REPORT_MESSAGE =
  "No rescue report yet; run claude-ollama rescue first";

export async function GET() {
  await connection();
  const report = latestRescueReport();
  if (report === null) {
    return NextResponse.json({ message: NO_REPORT_MESSAGE }, { status: 404 });
  }
  return NextResponse.json(report);
}

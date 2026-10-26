import { NextResponse } from "next/server";
import { readBenchOffReport } from "@/lib/bench-off-report";

export const dynamic = "force-dynamic";

const REPORT_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "Content-Security-Policy": "sandbox allow-scripts",
};

export function GET() {
  const report = readBenchOffReport(process.env);
  if (report === null) {
    return NextResponse.json({ message: "No bench-off report yet" }, { status: 404 });
  }
  return new NextResponse(report, { headers: REPORT_HEADERS });
}

import { connection, NextResponse } from "next/server";
import { BENCH_OFF_REPORT_HEADERS, readBenchOffReport } from "@/lib/bench-off-report";

export async function GET() {
  await connection();
  const report = readBenchOffReport(process.env);
  if (report === null) {
    return NextResponse.json({ message: "No bench-off report yet" }, { status: 404 });
  }
  return new NextResponse(report, { headers: BENCH_OFF_REPORT_HEADERS });
}

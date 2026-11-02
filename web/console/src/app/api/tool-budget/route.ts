import { connection, NextResponse } from "next/server";
import { consoleRepoDir } from "@/lib/sizes";
import { toolBudgetReport } from "@/lib/tool-budget-report";

export async function GET() {
  await connection();
  const result = await toolBudgetReport(process.env, consoleRepoDir());
  if (!result.ok) {
    return NextResponse.json({ message: result.message }, { status: 502 });
  }
  return NextResponse.json(result.report);
}

import { connection, NextResponse } from "next/server";
import { draftRows } from "@/lib/drafts";

export async function GET() {
  await connection();
  return NextResponse.json({ drafts: await draftRows() });
}

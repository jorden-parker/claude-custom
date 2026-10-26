import { connection, NextResponse } from "next/server";
import { listHistory } from "@/lib/history";

const LIST_LIMIT = 200;

export async function GET() {
  await connection();
  return NextResponse.json({ entries: listHistory().slice(0, LIST_LIMIT) });
}

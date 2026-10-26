import { connection, NextResponse } from "next/server";
import { modelsDeps, modelsSnapshot } from "@/lib/models";

export async function GET() {
  await connection();
  return NextResponse.json(await modelsSnapshot(modelsDeps()));
}

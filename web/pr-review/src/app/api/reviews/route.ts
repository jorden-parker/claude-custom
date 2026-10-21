import { connection, NextResponse } from "next/server";
import { listReviews } from "@/lib/reviews";

export async function GET() {
  await connection();
  return NextResponse.json(listReviews());
}

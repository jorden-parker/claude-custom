import { connection, NextResponse } from "next/server";
import { listRecipes } from "@/lib/recipes";
import { consoleRepoDir } from "@/lib/sizes";

export async function GET() {
  await connection();
  return NextResponse.json({ recipes: listRecipes(consoleRepoDir()) });
}

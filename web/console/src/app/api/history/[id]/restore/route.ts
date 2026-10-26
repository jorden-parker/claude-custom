import { connection, NextResponse } from "next/server";
import { restoreChange } from "@/lib/history";

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(_request: Request, context: RouteContext) {
  await connection();
  const { id } = await context.params;
  try {
    const result = restoreChange(id);
    if (!result.ok) {
      return NextResponse.json(
        { message: result.message },
        { status: result.status },
      );
    }
    return NextResponse.json({ entry: result.entry });
  } catch (error) {
    const message = error instanceof Error ? error.message : "restore failed";
    return NextResponse.json({ message }, { status: 500 });
  }
}

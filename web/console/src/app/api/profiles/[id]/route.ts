import { connection, NextResponse } from "next/server";
import { loadProfileBase, profileRules } from "@/lib/profile-base";
import { validateProfileOverride, type ProfileOverride } from "@/lib/profile-rules";
import { isKnownProfile, profileSummary, readOverride, saveOverride } from "@/lib/profiles";

type ProfileRouteContext = { params: Promise<{ id: string }> };

export async function GET(_request: Request, { params }: ProfileRouteContext) {
  await connection();
  const { id } = await params;
  if (!isKnownProfile(id)) {
    return failure("Unknown profile", 404);
  }
  const loaded = await loadProfileBase(id);
  if (!loaded.ok) {
    return failure(loaded.message, 502);
  }
  return NextResponse.json({ ...profileSummary(id), override: readOverride(id), base: loaded.base });
}

export async function PUT(request: Request, { params }: ProfileRouteContext) {
  await connection();
  const { id } = await params;
  if (!isKnownProfile(id)) {
    return failure("Unknown profile", 404);
  }
  const body: unknown = await request.json().catch(() => null);
  const loaded = await loadProfileBase(id);
  if (!loaded.ok) {
    return failure(loaded.message, 502);
  }
  const validation = validateProfileOverride(body, profileRules(id, loaded.base));
  if (!validation.ok) {
    return failure(validation.message, 400);
  }
  return save(id, validation.override);
}

function save(id: string, override: ProfileOverride) {
  try {
    saveOverride(id, override);
  } catch (error) {
    return failure(error instanceof Error ? error.message : "could not save the profile", 409);
  }
  return NextResponse.json({ override });
}

function failure(message: string, status: number) {
  return NextResponse.json({ message }, { status });
}

"use client";

import { useEffect, useState } from "react";
import type { ProfileSummary } from "@/lib/profiles";

export type ProfileSummaries = {
  profiles: ProfileSummary[] | null;
  error: string | null;
};

export function useProfileSummaries(): ProfileSummaries {
  const [profiles, setProfiles] = useState<ProfileSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void loadProfiles().then((result) => {
      if (result.ok) {
        setProfiles(result.profiles);
      } else {
        setError(result.message);
      }
    });
  }, []);

  return { profiles, error };
}

async function loadProfiles(): Promise<
  { ok: true; profiles: ProfileSummary[] } | { ok: false; message: string }
> {
  const response = await fetch("/api/profiles", { cache: "no-store" });
  if (!response.ok) {
    return {
      ok: false,
      message: `profiles failed with status ${response.status}`,
    };
  }
  const body = (await response.json()) as { profiles: ProfileSummary[] };
  return { ok: true, profiles: body.profiles };
}

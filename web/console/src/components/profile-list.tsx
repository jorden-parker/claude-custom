"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { ProfileSummary } from "@/lib/profiles";

export function ProfileList() {
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

  if (error !== null) {
    return <p className="text-sm text-error-foreground">{error}</p>;
  }
  if (profiles === null) {
    return <p className="text-sm text-muted-foreground">Loading profiles...</p>;
  }
  return (
    <ul className="grid gap-3 sm:grid-cols-2">
      {profiles.map((profile) => (
        <li key={profile.id}>
          <ProfileCard profile={profile} />
        </li>
      ))}
    </ul>
  );
}

function ProfileCard({ profile }: { profile: ProfileSummary }) {
  return (
    <Link href={`/profiles/${profile.id}`} className="block">
      <Card size="sm" className="h-full hover:bg-muted/40">
        <CardHeader>
          <CardTitle>{profile.title}</CardTitle>
          <CardDescription>{describe(profile)}</CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          {profile.overrides} {profile.overrides === 1 ? "override" : "overrides"}
        </CardContent>
      </Card>
    </Link>
  );
}

function describe(profile: ProfileSummary): string {
  if (profile.model === null) {
    return "Your Claude Code settings";
  }
  return profile.context === null ? profile.model : `${profile.model}, context ${profile.context}`;
}

async function loadProfiles(): Promise<{ ok: true; profiles: ProfileSummary[] } | { ok: false; message: string }> {
  const response = await fetch("/api/profiles", { cache: "no-store" });
  if (!response.ok) {
    return { ok: false, message: `profiles failed with status ${response.status}` };
  }
  const body = (await response.json()) as { profiles: ProfileSummary[] };
  return { ok: true, profiles: body.profiles };
}

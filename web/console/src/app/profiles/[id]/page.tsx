import { connection } from "next/server";
import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { ProfileEditor } from "@/components/profile-editor";
import { isKnownProfile, profileTitle } from "@/lib/profiles";

type ProfilePageProps = { params: Promise<{ id: string }> };

export default function ProfilePage({ params }: ProfilePageProps) {
  return (
    <Suspense fallback={<p className="text-sm text-muted-foreground">Loading profile...</p>}>
      <LiveProfile params={params} />
    </Suspense>
  );
}

async function LiveProfile({ params }: ProfilePageProps) {
  await connection();
  const { id } = await params;
  return (
    <>
      <PageHeading title={isKnownProfile(id) ? profileTitle(id) : "Profile"} backHref="/profiles" backLabel="Profiles" />
      <ProfileEditor id={id} />
    </>
  );
}

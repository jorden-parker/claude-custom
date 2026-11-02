import { connection } from "next/server";
import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { ProfileEditor } from "@/components/profile-editor";

type ProfilePageProps = { params: Promise<{ id: string }> };

export default function ProfilePage({ params }: ProfilePageProps) {
  return (
    <>
      <PageHeading title="Profile" backHref="/profiles" backLabel="Profiles" />
      <Suspense fallback={<p className="text-sm text-muted-foreground">Loading profile...</p>}>
        <LiveProfile params={params} />
      </Suspense>
    </>
  );
}

async function LiveProfile({ params }: ProfilePageProps) {
  await connection();
  const { id } = await params;
  return <ProfileEditor id={id} />;
}

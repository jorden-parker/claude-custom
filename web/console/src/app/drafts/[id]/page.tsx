import { connection } from "next/server";
import { Suspense } from "react";
import { DraftEditor } from "@/components/draft-editor";
import { PageHeading } from "@/components/page-heading";

type DraftPageProps = { params: Promise<{ id: string }> };

export default function DraftPage({ params }: DraftPageProps) {
  return (
    <>
      <PageHeading title="Draft" backHref="/drafts" backLabel="Drafts" />
      <Suspense
        fallback={
          <p className="text-sm text-muted-foreground">Loading draft...</p>
        }
      >
        <LiveDraft params={params} />
      </Suspense>
    </>
  );
}

async function LiveDraft({ params }: DraftPageProps) {
  await connection();
  const { id } = await params;
  return <DraftEditor id={id} />;
}

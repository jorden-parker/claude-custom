import Link from "next/link";
import { connection } from "next/server";
import { Suspense } from "react";
import { DraftEditor } from "@/components/draft-editor";

type DraftPageProps = { params: Promise<{ id: string }> };

export default function DraftPage({ params }: DraftPageProps) {
  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col gap-6 px-4 py-8">
      <Link href="/drafts" className="text-sm underline">
        All drafts
      </Link>
      <h1 className="text-2xl font-semibold">Draft</h1>
      <Suspense
        fallback={
          <p className="text-sm text-muted-foreground">Loading draft...</p>
        }
      >
        <LiveDraft params={params} />
      </Suspense>
    </main>
  );
}

async function LiveDraft({ params }: DraftPageProps) {
  await connection();
  const { id } = await params;
  return <DraftEditor id={id} />;
}

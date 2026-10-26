import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { RunView } from "@/components/run-view";
import { resolveRunFile } from "@/lib/run-log";

type RunPageProps = { params: Promise<{ id: string }> };

export default function RunPage({ params }: RunPageProps) {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/runs" className="text-sm underline">
        All runs
      </Link>
      <Suspense fallback={<p className="text-sm text-muted-foreground">Loading run...</p>}>
        <LiveRun params={params} />
      </Suspense>
    </main>
  );
}

async function LiveRun({ params }: RunPageProps) {
  await connection();
  const { id } = await params;
  if (!resolveRunFile(id)) {
    notFound();
  }
  return <RunView id={id} />;
}

import { notFound } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { RunView } from "@/components/run-view";
import { resolveRunFile } from "@/lib/run-log";

type RunPageProps = { params: Promise<{ id: string }> };

export default function RunPage({ params }: RunPageProps) {
  return (
    <>
      <PageHeading title="Run" backHref="/runs" backLabel="Runs" />
      <Suspense fallback={<p className="text-sm text-muted-foreground">Loading run...</p>}>
        <LiveRun params={params} />
      </Suspense>
    </>
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

import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { RunView } from "@/components/run-view";
import { resolveRunFile } from "@/lib/run-log";

type RunPageProps = { params: Promise<{ id: string }> };

export default async function RunPage({ params }: RunPageProps) {
  await connection();
  const { id } = await params;
  if (!resolveRunFile(id)) {
    notFound();
  }
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/runs" className="text-sm underline">
        All runs
      </Link>
      <RunView id={id} />
    </main>
  );
}

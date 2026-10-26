import Link from "next/link";
import { connection } from "next/server";
import { Suspense } from "react";
import { BenchForms } from "@/components/bench-forms";
import { BenchHistory } from "@/components/bench-history";
import { BenchOffFrame } from "@/components/bench-off-frame";
import { TelemetryCard } from "@/components/telemetry-card";
import { benchRuns } from "@/lib/bench-runs";
import { hasBenchOffReport } from "@/lib/bench-off-report";
import { listRuns } from "@/lib/run-log";
import { configuredSizes, consoleRepoDir } from "@/lib/sizes";
import { telemetryReport } from "@/lib/telemetry";

export default function BenchmarksPage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-8 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Benchmarks</h1>
      <Suspense fallback={<p className="text-sm text-muted-foreground">Loading benchmarks...</p>}>
        <BenchmarkSections />
      </Suspense>
    </main>
  );
}

async function BenchmarkSections() {
  await connection();
  const repoDir = consoleRepoDir();
  const telemetry = await telemetryReport(process.env, repoDir);
  return (
    <>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Run a bench</h2>
        <BenchForms sizes={configuredSizes(repoDir)} />
      </section>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Bench-off report</h2>
        <BenchOffFrame hasReport={hasBenchOffReport(process.env)} />
      </section>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">History</h2>
        <BenchHistory runs={benchRuns(listRuns())} />
      </section>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Tool telemetry</h2>
        <TelemetryCard report={telemetry} />
      </section>
    </>
  );
}

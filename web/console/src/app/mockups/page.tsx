import { connection } from "next/server";
import { Suspense } from "react";
import { BenchCard } from "@/components/bench-card";
import { BenchHistory } from "@/components/bench-history";
import { MockDiagnostics } from "@/components/mock-diagnostics";
import { LiveMockRun } from "@/components/live-mock-sheet";
import { MockSheet } from "@/components/mock-sheet";
import { PageHeading } from "@/components/page-heading";
import {
  listMockSpikeReports,
  mockSpikeDiagnostics,
} from "@/lib/mock-spike/reports.ts";
import { listRuns } from "@/lib/run-log";
import { configuredSizes, consoleRepoDir } from "@/lib/sizes";

const MOCK_SPIKE_COMMAND = "mock-spike";
const HISTORY_LIMIT = 10;

export default function MockupsPage() {
  return (
    <>
      <PageHeading title="Mockups" />
      <Suspense
        fallback={
          <p className="text-sm text-muted-foreground">Loading mockups...</p>
        }
      >
        <MockupSections />
      </Suspense>
    </>
  );
}

async function MockupSections() {
  await connection();
  const [report] = listMockSpikeReports();
  const runs = listRuns()
    .filter((run) => run.command === MOCK_SPIKE_COMMAND)
    .slice(0, HISTORY_LIMIT);
  const live = runs.find((run) => run.status === "running");
  return (
    <>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Run the spike</h2>
        <BenchCard
          title="Mock spike"
          description="Streams three mockup briefs through the size's model and scores the json-render patches; the run page shows its output live"
          command={MOCK_SPIKE_COMMAND}
          fields={[
            {
              key: "size",
              label: "Size",
              options: configuredSizes(consoleRepoDir()),
            },
          ]}
        />
      </section>
      {live ? (
        <section className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">Streaming now</h2>
          <LiveMockRun id={live.id} />
        </section>
      ) : null}
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Latest sheet</h2>
        {report ? (
          <MockSheet report={report} />
        ) : (
          <p className="text-sm text-muted-foreground">
            No report to draw yet.
          </p>
        )}
      </section>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Runs</h2>
        <BenchHistory runs={runs} />
      </section>
      <section className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">Report files</h2>
        <MockDiagnostics diagnostics={mockSpikeDiagnostics()} />
      </section>
    </>
  );
}

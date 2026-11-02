import { connection } from "next/server";
import { Suspense } from "react";
import { MockSheet } from "@/components/mock-sheet";
import { PageHeading } from "@/components/page-heading";
import { listMockSpikeReports, reportsDir } from "@/lib/mock-spike/reports.ts";

export default function MockupsPage() {
  return (
    <>
      <PageHeading title="Mockups" />
      <Suspense
        fallback={
          <p className="text-sm text-muted-foreground">Loading mockups...</p>
        }
      >
        <LatestSheet />
      </Suspense>
    </>
  );
}

async function LatestSheet() {
  await connection();
  const [report] = listMockSpikeReports();
  if (!report) {
    return (
      <p className="text-sm text-muted-foreground">
        No <code>mock-spike-*.json</code> in <code>{reportsDir()}</code>. Run{" "}
        <code>claude-ollama mock-spike [size]</code>, check it ends with a{" "}
        <code>saved:</code> line naming a file there, then reload.
      </p>
    );
  }
  return <MockSheet report={report} />;
}

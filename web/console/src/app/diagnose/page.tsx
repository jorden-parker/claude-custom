import { connection } from "next/server";
import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { RecipesCard } from "@/components/recipes-card";
import { RescueCard } from "@/components/rescue-card";
import { RuleCardsCard } from "@/components/rule-cards-card";
import { WhyCard } from "@/components/why-card";
import { listRuns } from "@/lib/run-log";
import { configuredSizes, consoleRepoDir } from "@/lib/sizes";

const WHY_COMMAND = "why";
const RESCUE_COMMAND = "rescue";

export default function DiagnosePage() {
  return (
    <>
      <PageHeading title="Diagnose" />
      <Suspense
        fallback={
          <p className="text-sm text-muted-foreground">
            Loading diagnostics...
          </p>
        }
      >
        <DiagnoseCards />
      </Suspense>
    </>
  );
}

async function DiagnoseCards() {
  await connection();
  const runs = listRuns();
  const latestRunId = (command: string) =>
    runs.find((run) => run.command === command)?.id ?? null;
  return (
    <div className="flex flex-col gap-4">
      <WhyCard initialRunId={latestRunId(WHY_COMMAND)} />
      <RescueCard
        sizes={configuredSizes(consoleRepoDir())}
        initialRunId={latestRunId(RESCUE_COMMAND)}
      />
      <RuleCardsCard />
      <RecipesCard />
    </div>
  );
}

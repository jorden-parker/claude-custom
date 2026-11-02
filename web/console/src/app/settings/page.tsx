import { PageHeading } from "@/components/page-heading";
import { SettingsOverview } from "@/components/settings-overview";
import { ToolBudgetCard } from "@/components/tool-budget-card";

export default function SettingsPage() {
  return (
    <>
      <PageHeading title="Settings" />
      <SettingsOverview />
      <ToolBudgetCard />
    </>
  );
}

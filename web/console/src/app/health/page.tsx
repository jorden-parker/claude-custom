import { HealthView } from "@/components/health-view";
import { PageHeading } from "@/components/page-heading";

export default function HealthPage() {
  return (
    <>
      <PageHeading title="Checks" />
      <HealthView />
    </>
  );
}

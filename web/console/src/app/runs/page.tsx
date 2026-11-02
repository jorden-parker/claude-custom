import { DoctorStartPanel } from "@/components/doctor-start-panel";
import { PageHeading } from "@/components/page-heading";
import { RunList } from "@/components/run-list";

export default function RunsPage() {
  return (
    <>
      <PageHeading title="Runs" />
      <DoctorStartPanel />
      <RunList />
    </>
  );
}

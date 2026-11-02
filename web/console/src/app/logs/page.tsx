import { LogView } from "@/components/log-view";
import { PageHeading } from "@/components/page-heading";

export default function LogsPage() {
  return (
    <>
      <PageHeading title="Logs" />
      <LogView />
    </>
  );
}

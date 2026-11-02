import { PageHeading } from "@/components/page-heading";
import { ResidencyCard } from "@/components/residency-card";
import { ServerEnvEditor } from "@/components/server-env-editor";

export default function ServerPage() {
  return (
    <>
      <PageHeading title="Server" />
      <ResidencyCard />
      <ServerEnvEditor />
    </>
  );
}

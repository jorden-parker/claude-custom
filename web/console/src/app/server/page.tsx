import { PageHeading } from "@/components/page-heading";
import { ResidencyCard } from "@/components/residency-card";
import { ServerIdentity } from "@/components/server-identity";
import { ServerSettingsEditor } from "@/components/server-settings-editor";

export default function ServerPage() {
  return (
    <>
      <PageHeading title="Server" />
      <ServerIdentity />
      <ResidencyCard />
      <ServerSettingsEditor />
    </>
  );
}

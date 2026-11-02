import { PageHeading } from "@/components/page-heading";
import { ServerEnvEditor } from "@/components/server-env-editor";

export default function ServerPage() {
  return (
    <>
      <PageHeading title="Server" />
      <ServerEnvEditor />
    </>
  );
}

import { PageHeading } from "@/components/page-heading";
import { WorkspaceList } from "@/components/workspace-list";

export default function WorkspacesPage() {
  return (
    <>
      <PageHeading title="Workspaces" />
      <WorkspaceList />
    </>
  );
}

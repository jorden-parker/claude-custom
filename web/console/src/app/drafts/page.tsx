import { DraftList } from "@/components/draft-list";
import { PageHeading } from "@/components/page-heading";

export default function DraftsPage() {
  return (
    <>
      <PageHeading title="Drafts" />
      <DraftList />
    </>
  );
}

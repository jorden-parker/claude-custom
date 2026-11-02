import { FetchDomainsEditor } from "@/components/fetch-domains-editor";
import { PageHeading } from "@/components/page-heading";

export default function FetchDomainsPage() {
  return (
    <>
      <PageHeading title="Fetch domains" />
      <FetchDomainsEditor />
    </>
  );
}

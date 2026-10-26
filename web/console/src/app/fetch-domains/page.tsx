import Link from "next/link";
import { FetchDomainsEditor } from "@/components/fetch-domains-editor";

export default function FetchDomainsPage() {
  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Fetch domains</h1>
      <FetchDomainsEditor />
    </main>
  );
}

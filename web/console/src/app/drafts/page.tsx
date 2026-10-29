import { DraftList } from "@/components/draft-list";

export default function DraftsPage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <h1 className="text-2xl font-semibold">Drafts</h1>
      <DraftList />
    </main>
  );
}

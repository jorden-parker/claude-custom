import Link from "next/link";
import { HistoryView } from "@/components/history-view";

export default function HistoryPage() {
  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">History</h1>
      <HistoryView />
    </main>
  );
}

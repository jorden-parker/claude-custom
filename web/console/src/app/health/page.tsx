import Link from "next/link";
import { HealthView } from "@/components/health-view";

export default function HealthPage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Health</h1>
      <HealthView />
    </main>
  );
}

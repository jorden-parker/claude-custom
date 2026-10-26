import Link from "next/link";
import { DoctorStartPanel } from "@/components/doctor-start-panel";
import { RunList } from "@/components/run-list";

export default function RunsPage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Runs</h1>
      <DoctorStartPanel />
      <RunList />
    </main>
  );
}

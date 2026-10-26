import Link from "next/link";
import { connection } from "next/server";
import { SpeedHistory } from "@/components/speed-history";
import { failedSpeedChecks } from "@/lib/speed-failures";
import { listSpeedReports } from "@/lib/speed-reports";

export default async function SpeedCheckPage() {
  await connection();
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Speed check</h1>
      <SpeedHistory reports={listSpeedReports()} failures={failedSpeedChecks()} />
    </main>
  );
}

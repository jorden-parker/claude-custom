import Link from "next/link";
import { ServerEnvEditor } from "@/components/server-env-editor";

export default function ServerPage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Server</h1>
      <ServerEnvEditor />
    </main>
  );
}

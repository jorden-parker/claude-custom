import Link from "next/link";
import { ToolsEditor } from "@/components/tools-editor";

export default function ToolsPage() {
  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        Console home
      </Link>
      <h1 className="text-2xl font-semibold">Tools</h1>
      <ToolsEditor />
    </main>
  );
}

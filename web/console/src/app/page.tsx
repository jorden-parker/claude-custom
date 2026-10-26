import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { CONSOLE_SECTIONS } from "@/lib/console-sections";

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <h1 className="text-2xl font-semibold">claude-ollama</h1>
      <ul className="flex flex-col gap-3">
        {CONSOLE_SECTIONS.map((section) => (
          <li key={section.href}>
            <Link
              href={section.href}
              className="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <Card className="cursor-pointer transition-colors hover:bg-muted/60">
                <CardContent className="flex flex-col gap-1">
                  <span className="font-medium">{section.title}</span>
                  <span className="text-sm text-muted-foreground">{section.summary}</span>
                </CardContent>
              </Card>
            </Link>
          </li>
        ))}
      </ul>
    </main>
  );
}

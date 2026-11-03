import Link from "next/link";
import { PageHeading } from "@/components/page-heading";
import { SectionIcon } from "@/components/section-icon";
import { Card, CardContent } from "@/components/ui/card";
import { CONSOLE_SECTIONS } from "@/lib/console-sections";

export default function Home() {
  return (
    <>
      <PageHeading title="claude-ollama" />
      <ul className="grid gap-3 sm:grid-cols-2">
        {CONSOLE_SECTIONS.map((section) => (
          <li key={section.href}>
            <Link
              href={section.href}
              className="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <Card className="cursor-pointer transition-colors hover:bg-accent">
                <CardContent className="flex flex-col gap-1">
                  <span className="flex items-center gap-2 font-medium">
                    <SectionIcon href={section.href} />
                    {section.title}
                  </span>
                  <span className="text-sm text-muted-foreground">{section.summary}</span>
                </CardContent>
              </Card>
            </Link>
          </li>
        ))}
      </ul>
    </>
  );
}

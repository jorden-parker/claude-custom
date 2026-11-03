import Link from "next/link";
import { PageHeading } from "@/components/page-heading";
import { SectionIcon } from "@/components/section-icon";
import { Card, CardContent } from "@/components/ui/card";
import {
  CONSOLE_SECTION_GROUPS,
  sectionsInGroup,
  type ConsoleSection,
} from "@/lib/console-sections";

export default function Home() {
  return (
    <>
      <PageHeading
        title="claude-ollama"
        description="Configure, run and review the local claude-ollama harness"
      />
      {CONSOLE_SECTION_GROUPS.map((group) => (
        <section key={group} className="flex flex-col gap-3">
          <h2 className="text-sm font-medium text-muted-foreground">{group}</h2>
          <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {sectionsInGroup(group).map((section) => (
              <li key={section.href}>
                <SectionCard section={section} />
              </li>
            ))}
          </ul>
        </section>
      ))}
    </>
  );
}

function SectionCard({ section }: { section: ConsoleSection }) {
  return (
    <Link
      href={section.href}
      className="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <Card className="h-full cursor-pointer transition-colors hover:bg-accent">
        <CardContent className="flex items-start gap-3">
          <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-md border bg-muted text-muted-foreground">
            <SectionIcon href={section.href} className="size-4" />
          </span>
          <span className="flex min-w-0 flex-col gap-1">
            <span className="font-medium">{section.title}</span>
            <span className="text-sm text-muted-foreground">
              {section.summary}
            </span>
          </span>
        </CardContent>
      </Card>
    </Link>
  );
}

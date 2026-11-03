import Link from "next/link";
import { SectionIcon } from "@/components/section-icon";
import { Card, CardContent } from "@/components/ui/card";
import type { ConsoleSection } from "@/lib/console-sections";

export function SectionCard({ section }: { section: ConsoleSection }) {
  return (
    <Link
      href={section.href}
      className="block h-full rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <Card className="h-full cursor-pointer transition-colors hover:bg-accent">
        <CardContent className="flex items-start gap-3">
          <span className="inline-flex size-8 shrink-0 items-center justify-center rounded-md border bg-muted text-muted-foreground">
            <SectionIcon href={section.href} className="size-4" />
          </span>
          <span className="flex min-w-0 flex-col gap-1">
            <span className="font-medium">{section.title}</span>
            <span
              className="line-clamp-2 min-h-10 text-sm text-muted-foreground"
              title={section.summary}
            >
              {section.summary}
            </span>
          </span>
        </CardContent>
      </Card>
    </Link>
  );
}

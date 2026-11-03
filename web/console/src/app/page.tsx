import { PageHeading } from "@/components/page-heading";
import { SectionCard } from "@/components/section-card";
import {
  CONSOLE_SECTION_GROUPS,
  sectionsInGroup,
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

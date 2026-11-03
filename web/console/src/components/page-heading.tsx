import Link from "next/link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { sectionSummaryForTitle } from "@/lib/console-sections";

type PageHeadingProps = {
  title: string;
  backHref?: string;
  backLabel?: string;
  description?: string;
};

const HEADING_CLASS = "min-w-0 break-words text-heading-24 sm:text-heading-32";

function Title({ title, backHref, backLabel }: PageHeadingProps) {
  if (backHref && backLabel) {
    return (
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink render={<Link href={backHref} />}>
              {backLabel}
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <h1 aria-current="page" className={HEADING_CLASS}>
              {title}
            </h1>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>
    );
  }
  return <h1 className={HEADING_CLASS}>{title}</h1>;
}

export function PageHeading(props: PageHeadingProps) {
  const subtitle = props.description ?? sectionSummaryForTitle(props.title);
  return (
    <header className="flex flex-col gap-1">
      <Title {...props} />
      {subtitle === undefined ? null : (
        <p className="text-copy-14 text-muted-foreground">{subtitle}</p>
      )}
    </header>
  );
}

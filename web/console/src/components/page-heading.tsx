import Link from "next/link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { subtitleFor } from "@/lib/whimsy-copy";

type PageHeadingProps = {
  title: string;
  backHref?: string;
  backLabel?: string;
};

const HEADING_CLASS = "min-w-0 break-words font-heading text-2xl font-semibold tracking-heading sm:text-3xl";

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
  return (
    <header className="flex flex-col gap-1">
      <Title {...props} />
      <p className="text-sm text-muted-foreground">{subtitleFor(props.title)}</p>
    </header>
  );
}

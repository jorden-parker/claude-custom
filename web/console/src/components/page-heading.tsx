import Link from "next/link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";

type PageHeadingProps = {
  title: string;
  backHref?: string;
  backLabel?: string;
};

const HEADING_CLASS = "text-2xl font-semibold tracking-heading";

export function PageHeading({ title, backHref, backLabel }: PageHeadingProps) {
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

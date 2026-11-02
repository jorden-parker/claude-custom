import Link from "next/link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";

type PageHeadingProps = {
  title: string;
  backHref?: string;
  backLabel?: string;
};

export function PageHeading({ title, backHref, backLabel }: PageHeadingProps) {
  return (
    <div className="flex flex-col gap-2">
      {backHref && backLabel ? (
        <Breadcrumb>
          <BreadcrumbList>
            <BreadcrumbItem>
              <BreadcrumbLink render={<Link href={backHref} />}>
                {backLabel}
              </BreadcrumbLink>
            </BreadcrumbItem>
            <BreadcrumbSeparator />
            <BreadcrumbItem>
              <BreadcrumbPage>{title}</BreadcrumbPage>
            </BreadcrumbItem>
          </BreadcrumbList>
        </Breadcrumb>
      ) : null}
      <h1 className="text-2xl font-semibold tracking-heading">{title}</h1>
    </div>
  );
}

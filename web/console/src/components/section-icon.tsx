import {
  Boxes,
  ChartColumn,
  FolderCheck,
  Gauge,
  GitPullRequest,
  Globe,
  History,
  House,
  LayoutTemplate,
  LifeBuoy,
  NotebookPen,
  Play,
  ScrollText,
  Server,
  Settings2,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Stethoscope,
  Wrench,
  type LucideIcon,
} from "lucide-react";

const ICON_BY_HREF: Record<string, LucideIcon | undefined> = {
  "/": House,
  "/reviews": GitPullRequest,
  "/drafts": NotebookPen,
  "/runs": Play,
  "/health": Stethoscope,
  "/logs": ScrollText,
  "/diagnose": LifeBuoy,
  "/server": Server,
  "/speed-check": Gauge,
  "/tools": Wrench,
  "/profiles": SlidersHorizontal,
  "/settings": Settings2,
  "/benchmarks": ChartColumn,
  "/mockups": LayoutTemplate,
  "/models": Boxes,
  "/fetch-domains": Globe,
  "/machine": ShieldCheck,
  "/workspaces": FolderCheck,
  "/history": History,
};

export function SectionIcon({
  href,
  className,
}: {
  href: string;
  className?: string;
}) {
  const Icon = ICON_BY_HREF[href] ?? Sparkles;
  return <Icon aria-hidden="true" className={className} />;
}

import {
  Boxes,
  ChartColumn,
  Gauge,
  GitPullRequest,
  Globe,
  History,
  House,
  NotebookPen,
  Play,
  ScrollText,
  Server,
  ShieldCheck,
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
  "/server": Server,
  "/speed-check": Gauge,
  "/tools": Wrench,
  "/benchmarks": ChartColumn,
  "/models": Boxes,
  "/fetch-domains": Globe,
  "/machine": ShieldCheck,
  "/history": History,
};

export function SectionIcon({ href }: { href: string }) {
  const Icon = ICON_BY_HREF[href] ?? Sparkles;
  return <Icon className="size-4" aria-hidden="true" />;
}

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
import { cn } from "cn";
import { pickStable } from "@/lib/whimsy-copy";

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

const CHIP_TONES: readonly string[] = [
  "bg-success text-success-foreground",
  "bg-info text-info-foreground",
  "bg-warning text-warning-foreground",
  "bg-error text-error-foreground",
  "bg-secondary text-secondary-foreground",
  "bg-accent text-accent-foreground",
];

export function SectionIcon({ href }: { href: string }) {
  const Icon = ICON_BY_HREF[href] ?? Sparkles;
  return (
    <span
      aria-hidden="true"
      className={cn(
        "inline-flex size-6 shrink-0 items-center justify-center rounded-full border-2 border-ink",
        pickStable(CHIP_TONES, href),
      )}
    >
      <Icon className="size-3.5" />
    </span>
  );
}

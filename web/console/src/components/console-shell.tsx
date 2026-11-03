import Link from "next/link";
import { Suspense, type ReactNode } from "react";
import { BrandMark } from "@/components/brand-mark";
import { ConsoleNav } from "@/components/console-nav";
import {
  Sidebar,
  SidebarInset,
  SidebarProvider,
  SidebarRail,
  SidebarTrigger,
} from "@/components/ui/sidebar";

export function ConsoleShell({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <SidebarProvider>
      <Sidebar collapsible="icon">
        <Suspense>
          <ConsoleNav />
        </Suspense>
        <SidebarRail />
      </Sidebar>
      <SidebarInset className="min-w-0">
        <header className="sticky top-0 z-10 flex h-12 md:hidden items-center gap-2 border-b bg-background/80 px-3 backdrop-blur supports-[backdrop-filter]:bg-background/60 sm:px-4">
          <SidebarTrigger />
          <Link
            href="/"
            className="flex items-center gap-2 text-sm font-semibold"
          >
            <BrandMark />
            claude-ollama
          </Link>
        </header>
        <div className="mx-auto flex w-full max-w-(--ds-page-width) flex-col gap-5 px-4 py-6 sm:gap-6 sm:px-6 sm:py-8 lg:px-8">
          {children}
        </div>
      </SidebarInset>
    </SidebarProvider>
  );
}

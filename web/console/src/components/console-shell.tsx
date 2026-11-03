import { Suspense, type ReactNode } from "react";
import { ConsoleNav } from "@/components/console-nav";
import {
  Sidebar,
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";

export function ConsoleShell({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <SidebarProvider>
      <Sidebar collapsible="icon">
        <Suspense>
          <ConsoleNav />
        </Suspense>
      </Sidebar>
      <SidebarInset>
        <header className="sticky top-0 z-10 flex h-12 items-center gap-2 border-b bg-background/80 px-3 backdrop-blur supports-[backdrop-filter]:bg-background/60 sm:px-4">
          <SidebarTrigger />
        </header>
        <main className="mx-auto flex w-full max-w-(--ds-page-width) flex-col gap-5 px-4 py-6 sm:gap-6 sm:px-6 sm:py-8 lg:px-8">
          {children}
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}

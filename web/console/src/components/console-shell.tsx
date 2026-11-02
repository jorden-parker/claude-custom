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
        <header className="flex h-12 items-center gap-2 border-b px-4">
          <SidebarTrigger />
        </header>
        <main className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-8">
          {children}
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}

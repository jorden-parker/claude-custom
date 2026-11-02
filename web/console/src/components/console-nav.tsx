"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { GardenSprite } from "@/components/garden-sprite";
import { SectionIcon } from "@/components/section-icon";
import {
  SidebarContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { CONSOLE_SECTIONS } from "@/lib/console-sections";

export function isActiveSection(pathname: string, href: string): boolean {
  if (href === "/") {
    return pathname === "/";
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function ConsoleNav() {
  const pathname = usePathname();

  return (
    <>
      <SidebarHeader>
        <Link
          href="/"
          className="flex items-center gap-2 px-2 py-1.5 font-heading text-lg font-semibold tracking-heading"
        >
          <GardenSprite />
          claude-ollama
        </Link>
      </SidebarHeader>
      <SidebarContent>
        <SidebarMenu>
          {CONSOLE_SECTIONS.map((section) => (
            <SidebarMenuItem key={section.href}>
              <SidebarMenuButton
                render={<Link href={section.href} />}
                isActive={isActiveSection(pathname, section.href)}
                tooltip={section.summary}
              >
                <SectionIcon href={section.href} />
                <span>{section.title}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          ))}
        </SidebarMenu>
      </SidebarContent>
    </>
  );
}

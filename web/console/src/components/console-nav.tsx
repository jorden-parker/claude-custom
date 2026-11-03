"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { BrandMark } from "@/components/brand-mark";
import { SectionIcon } from "@/components/section-icon";
import {
  SidebarContent,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar";
import {
  CONSOLE_SECTION_GROUPS,
  sectionsInGroup,
} from "@/lib/console-sections";

export function isActiveSection(pathname: string, href: string): boolean {
  if (href === "/") {
    return pathname === "/";
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function ConsoleNav() {
  const pathname = usePathname();
  const { isMobile, setOpenMobile } = useSidebar();

  const closeMobileSheet = () => {
    if (isMobile) {
      setOpenMobile(false);
    }
  };

  return (
    <>
      <SidebarHeader>
        <Link
          href="/"
          className="flex items-center gap-2 px-2 py-1.5 text-sm font-semibold"
        >
          <BrandMark />
          claude-ollama
        </Link>
      </SidebarHeader>
      <SidebarContent>
        {CONSOLE_SECTION_GROUPS.map((group) => (
          <SidebarGroup key={group}>
            <SidebarGroupLabel>{group}</SidebarGroupLabel>
            <SidebarMenu>
              {sectionsInGroup(group).map((section) => (
                <SidebarMenuItem key={section.href}>
                  <SidebarMenuButton
                    render={<Link href={section.href} />}
                    isActive={isActiveSection(pathname, section.href)}
                    tooltip={section.summary}
                    onClick={closeMobileSheet}
                  >
                    <SectionIcon href={section.href} />
                    <span>{section.title}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroup>
        ))}
      </SidebarContent>
    </>
  );
}

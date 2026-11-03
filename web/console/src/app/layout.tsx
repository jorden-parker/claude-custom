import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Geist, Geist_Mono } from "next/font/google";
import { ConsoleShell } from "@/components/console-shell";
import "./globals.css";

const geistSans = Geist({
  weight: ["400", "500", "600"],
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  weight: ["400", "500", "600"],
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "claude-ollama console",
  description: "Configure, run and review the local claude-ollama harness",
};

export default function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <ConsoleShell>{children}</ConsoleShell>
      </body>
    </html>
  );
}

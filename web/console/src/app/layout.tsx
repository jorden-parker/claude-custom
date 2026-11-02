import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Fraunces, Geist_Mono, Nunito } from "next/font/google";
import { ConsoleShell } from "@/components/console-shell";
import "./globals.css";

const fraunces = Fraunces({
  weight: "variable",
  axes: ["SOFT", "WONK"],
  variable: "--font-fraunces",
  subsets: ["latin"],
});

const nunito = Nunito({
  weight: "variable",
  variable: "--font-nunito",
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
      className={`${fraunces.variable} ${nunito.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <ConsoleShell>{children}</ConsoleShell>
      </body>
    </html>
  );
}

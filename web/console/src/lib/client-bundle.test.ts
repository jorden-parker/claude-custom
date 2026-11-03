import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const SOURCE_ROOT = path.resolve(__dirname, "..");
const SOURCE_SUFFIXES = [".ts", ".tsx", "/index.ts", "/index.tsx"];
const VALUE_IMPORT = /^import\s+(?!type\s)[^;]*?from\s+"([^"]+)"/gm;

function listSourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) return listSourceFiles(entryPath);
    const isSource = /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name);
    return isSource ? [entryPath] : [];
  });
}

function resolveLocal(fromFile: string, specifier: string): string | null {
  const base = specifier.startsWith("@/")
    ? path.join(SOURCE_ROOT, specifier.slice(2))
    : specifier.startsWith(".")
      ? path.resolve(path.dirname(fromFile), specifier)
      : null;
  if (!base) return null;
  const candidates = SOURCE_SUFFIXES.map((suffix) => base + suffix);
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? null;
}

function nodeImportChain(file: string, seen: Set<string>): string[] | null {
  if (seen.has(file)) return null;
  seen.add(file);
  const text = fs.readFileSync(file, "utf8");
  for (const match of text.matchAll(VALUE_IMPORT)) {
    const specifier = match[1];
    if (specifier.startsWith("node:")) return [file, specifier];
    const local = resolveLocal(file, specifier);
    const chain = local && nodeImportChain(local, seen);
    if (chain) return [file, ...chain];
  }
  return null;
}

describe("client components", () => {
  const clientFiles = listSourceFiles(SOURCE_ROOT).filter((file) =>
    fs.readFileSync(file, "utf8").startsWith('"use client"'),
  );

  it.each(clientFiles.map((file) => [path.relative(SOURCE_ROOT, file), file]))(
    "%s never reaches a node: module",
    (_name, file) => {
      const chain = nodeImportChain(file, new Set());
      const readableChain = chain ? chain.map((step) => path.relative(SOURCE_ROOT, step)) : [];
      expect(readableChain).toEqual([]);
    },
  );
});

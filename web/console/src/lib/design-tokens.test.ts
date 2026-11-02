import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const sourceRoot = fileURLToPath(new URL("..", import.meta.url));
const globalsPath = path.join(sourceRoot, "app", "globals.css");
const vendoredUiDir = path.join(sourceRoot, "components", "ui");
const semanticDeclaration = /^\s*--(background|foreground|card|primary|secondary|muted|accent|destructive|border|input|ring|radius|sidebar|chart|success|warning|error|info|neutral)[a-z0-9-]*:\s*(.*);$/;
const rawColourLiteral = /#[0-9a-fA-F]{3,8}\b|oklch\(|hsl\(|rgb\(/;

function sourceFiles(directory: string): string[] {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return entryPath === vendoredUiDir ? [] : sourceFiles(entryPath);
    }
    return isCheckedSource(entryPath) ? [entryPath] : [];
  });
}

function isCheckedSource(filePath: string): boolean {
  return /\.(ts|tsx|css)$/.test(filePath) && !/\.test\./.test(filePath) && filePath !== globalsPath;
}

describe("design tokens", () => {
  it("resolves every semantic variable through a token", () => {
    const declarations = fs
      .readFileSync(globalsPath, "utf8")
      .split("\n")
      .map((line) => semanticDeclaration.exec(line))
      .filter((match): match is RegExpExecArray => match !== null);

    expect(declarations.length).toBeGreaterThan(0);
    for (const [line, , value] of declarations) {
      expect(value, line).toContain("var(");
    }
  });

  it("keeps raw colour literals out of every component and lib file", () => {
    const offenders = sourceFiles(path.join(sourceRoot)).filter((filePath) =>
      rawColourLiteral.test(fs.readFileSync(filePath, "utf8")),
    );

    expect(offenders.map((filePath) => path.relative(sourceRoot, filePath))).toEqual([]);
  });
});

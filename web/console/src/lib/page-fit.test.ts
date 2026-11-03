import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const sourceRoot = fileURLToPath(new URL("..", import.meta.url));
const skippedDirectories = [
  path.join(sourceRoot, "components", "ui"),
  path.join(sourceRoot, "components", "ai-elements"),
];
const streamOutputPath = path.join(
  sourceRoot,
  "components",
  "stream-output.tsx",
);

function pageSources(directory: string): string[] {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return skippedDirectories.includes(entryPath)
        ? []
        : pageSources(entryPath);
    }
    return /\.tsx$/.test(entryPath) && !/\.test\./.test(entryPath)
      ? [entryPath]
      : [];
  });
}

const sources = [
  ...pageSources(path.join(sourceRoot, "components")),
  ...pageSources(path.join(sourceRoot, "app")),
].map((filePath) => ({
  filePath,
  text: fs.readFileSync(filePath, "utf8"),
}));

describe("page fit", () => {
  it("never scrolls text inside a scroll area", () => {
    const offenders = sources
      .filter(({ text }) => text.includes("@/components/ui/scroll-area"))
      .map(({ filePath }) => filePath);
    expect(offenders).toEqual([]);
  });

  it("caps a height only in the live stream box", () => {
    const offenders = sources
      .filter(({ text }) => text.includes("max-h-"))
      .map(({ filePath }) => filePath)
      .filter((filePath) => filePath !== streamOutputPath);
    expect(offenders).toEqual([]);
  });

  it("wraps preformatted text", () => {
    const offenders = sources
      .filter(({ text }) => /whitespace-pre(?![-\w])/.test(text))
      .map(({ filePath }) => filePath);
    expect(offenders).toEqual([]);
  });

  it("keeps a sideways-scrolling tab bar from scrolling vertically", () => {
    const tabBarClasses = sources.flatMap(({ text }) =>
      [...text.matchAll(/<TabsList\s+className="([^"]*)"/g)].map(
        (match) => match[1],
      ),
    );
    const sidewaysOnly = tabBarClasses.filter((classes) =>
      classes.includes("overflow-x-auto"),
    );
    expect(sidewaysOnly.length).toBeGreaterThan(0);
    for (const classes of sidewaysOnly) {
      expect(classes).toContain("overflow-y-hidden");
    }
  });
});

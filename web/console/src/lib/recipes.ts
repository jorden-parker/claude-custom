import fs from "node:fs";
import path from "node:path";
import { parseRecipeEntries, type HookRecipes } from "./diagnose";

const RECIPES_DIR = path.join("ollama", "recipes");
const RECIPE_SUFFIX = ".json";

export function listRecipes(repoDir: string): HookRecipes[] {
  const dir = path.join(repoDir, RECIPES_DIR);
  if (repoDir === "" || !fs.existsSync(dir)) {
    return [];
  }
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith(RECIPE_SUFFIX))
    .sort()
    .map((name) => ({
      hook: name.slice(0, -RECIPE_SUFFIX.length),
      entries: parseRecipeEntries(
        fs.readFileSync(path.join(dir, name), "utf8"),
      ),
    }));
}

import fs from "node:fs";
import path from "node:path";
import { parseRuleCard, parseRuleCardList, type RuleCard } from "./diagnose";
import { runOnce } from "./run-once";

export type RuleCardsResult =
  { ok: true; cards: RuleCard[] } | { ok: false; message: string };

const LIST_TIMEOUT_MS = 20_000;
const LIST_MAX_BYTES = 1_000_000;
const CARDS_DIR = path.join("ollama", "rule-cards");
const CARD_SUFFIX = ".md";

function ruleCardsListArgv(repoDir: string): string[] {
  return [`${repoDir}/shared/hooks/rule-cards.py`, "--list"];
}

export async function listRuleCards(repoDir: string): Promise<RuleCardsResult> {
  const result = await runOnce(ruleCardsListArgv(repoDir), {
    timeoutMs: LIST_TIMEOUT_MS,
    maxBytes: LIST_MAX_BYTES,
  });
  if (result.code !== 0) {
    return {
      ok: false,
      message: result.stderr.trim() || "rule-cards.py --list failed",
    };
  }
  const cards = parseRuleCardList(result.stdout).map(({ id, triggers }) => ({
    ...parseRuleCard(id, cardText(repoDir, id)),
    triggers,
  }));
  return { ok: true, cards };
}

function cardText(repoDir: string, id: string): string {
  const file = path.join(repoDir, CARDS_DIR, `${id}${CARD_SUFFIX}`);
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
}

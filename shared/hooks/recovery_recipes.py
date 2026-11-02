import json
import re
from pathlib import Path

RECIPES_DIR = Path(__file__).resolve().parents[2] / "ollama" / "recipes"
STEP_LIMIT = 3


def load_recipes(hook):
    try:
        return json.loads((RECIPES_DIR / f"{hook}.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []


def recipe_steps(hook, reason):
    for recipe in load_recipes(hook):
        if re.search(recipe["match"], reason):
            return recipe["steps"][:STEP_LIMIT]
    return []


def numbered_steps(steps):
    return "; ".join(f"{number}. {step}" for number, step in enumerate(steps[:STEP_LIMIT], 1))


def recovery_line(hook, reason):
    steps = recipe_steps(hook, reason)
    return f" Recovery: {numbered_steps(steps)}." if steps else ""

import json
from pathlib import Path

CATALOGUE = Path(__file__).resolve().parent.parent / "profile-env.json"


def catalogue_default(key):
    for entry in json.loads(CATALOGUE.read_text()):
        if entry["key"] == key:
            return entry["default"]
    raise KeyError(key)

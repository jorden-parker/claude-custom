#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from relaunch_dir import RelaunchDir

PROMPT_LIMIT = 200
SKIPPED_PROMPT_STARTS = ("/", "<system-reminder>", "<local-command")
BLOCK_REASON = "Context budget at {percent}%: call the handoff skill with save now, then stop."


def claude_config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def state_path(session_id):
    return claude_config_dir() / "cache" / "context-budget" / f"{session_id}.json"


def load_state(path):
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    return state if isinstance(state, dict) else None


def handoff_notes_dir(cwd):
    try:
        common_dir = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--git-common-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(cwd, common_dir) / "handoff"


def newest_note_since(notes_dir, nudged_at):
    try:
        notes = [note for note in notes_dir.iterdir() if note.suffix == ".md" and note.is_file()]
    except OSError:
        return None
    fresh = [note for note in notes if note.stat().st_mtime >= nudged_at]
    return max(fresh, key=lambda note: note.stat().st_mtime, default=None)


def fresh_note(event, state):
    notes_dir = handoff_notes_dir(event.get("cwd") or os.getcwd())
    if notes_dir is None:
        return None
    return newest_note_since(notes_dir, float(state["nudged_at"]))


def text_of(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    if any(not isinstance(block, dict) or block.get("type") != "text" for block in content):
        return None
    return " ".join(str(block.get("text", "")) for block in content)


def usable_prompt(text):
    if text is None:
        return None
    collapsed = " ".join(text.split())
    if not collapsed or collapsed.startswith(SKIPPED_PROMPT_STARTS):
        return None
    return collapsed[:PROMPT_LIMIT]


def transcript_entries(transcript_path):
    try:
        lines = Path(transcript_path).read_text(encoding="utf-8").splitlines()
    except (OSError, TypeError):
        return []
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue
    return [entry for entry in entries if isinstance(entry, dict)]


def last_user_prompt(transcript_path):
    for entry in reversed(transcript_entries(transcript_path)):
        if entry.get("type") != "user":
            continue
        message = entry.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        prompt = usable_prompt(text_of(content))
        if prompt:
            return prompt
    return ""


def request_relaunch(folder, note, event, state):
    folder.request(
        "relaunch",
        {
            "note": str(note),
            "prompt": last_user_prompt(event.get("transcript_path")),
            "percent": state.get("percent"),
        },
    )


def may_block(event, state):
    return not event.get("stop_hook_active") and not state.get("blocked_once")


def block_for_save(path, state):
    path.write_text(json.dumps({**state, "blocked_once": True}))
    reason = BLOCK_REASON.format(percent=state.get("percent", "?"))
    print(json.dumps({"decision": "block", "reason": reason}))


def relaunch(event, folder):
    path = state_path(event.get("session_id", "nosession"))
    state = load_state(path)
    if not state or "nudged_at" not in state or state.get("relaunched"):
        return
    note = fresh_note(event, state)
    if note is None:
        if may_block(event, state):
            block_for_save(path, state)
        return
    path.write_text(json.dumps({**state, "relaunched": True}))
    request_relaunch(folder, note, event, state)
    folder.terminate_claude()


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--inspect":
        print(last_user_prompt(sys.argv[2]))
        return
    event = json.load(sys.stdin)
    folder = RelaunchDir.from_env()
    if event.get("hook_event_name") != "Stop" or folder is None:
        return
    try:
        relaunch(event, folder)
    except (OSError, ValueError) as error:
        print(f"handoff-relaunch: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()

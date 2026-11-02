#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

CLAUDE_PROCESS_NAMES = ("node", "claude")


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


def is_claude_process(pid):
    try:
        comm = subprocess.run(
            ["ps", "-o", "comm=", "-p", str(pid)], capture_output=True, text=True, check=False
        ).stdout.strip()
    except OSError:
        return False
    return any(name in Path(comm).name for name in CLAUDE_PROCESS_NAMES)


def terminate_claude(relaunch_dir):
    try:
        pid = int((relaunch_dir / "claude.pid").read_text().strip())
    except (OSError, ValueError):
        return
    if pid > 0 and is_claude_process(pid):
        os.kill(pid, signal.SIGTERM)


def relaunch(event, relaunch_dir):
    path = state_path(event.get("session_id", "nosession"))
    state = load_state(path)
    if not state or "nudged_at" not in state or state.get("relaunched"):
        return
    notes_dir = handoff_notes_dir(event.get("cwd") or os.getcwd())
    note = notes_dir and newest_note_since(notes_dir, float(state["nudged_at"]))
    if note is None:
        return
    path.write_text(json.dumps({**state, "relaunched": True}))
    (relaunch_dir / "relaunch").write_text(str(note))
    terminate_claude(relaunch_dir)


def main():
    event = json.load(sys.stdin)
    relaunch_dir = os.environ.get("CLAUDE_OLLAMA_RELAUNCH_DIR")
    if event.get("hook_event_name") != "Stop" or not relaunch_dir:
        return
    try:
        relaunch(event, Path(relaunch_dir))
    except OSError as error:
        print(f"handoff-relaunch: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()

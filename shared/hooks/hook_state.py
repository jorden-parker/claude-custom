#!/usr/bin/env python3
import contextlib
import copy
import fcntl
import json
import os
import re
import shutil
import tempfile
import time
from pathlib import Path

UNSAFE_ID_CHARACTERS = re.compile(r"[^A-Za-z0-9._-]")
SECONDS_PER_DAY = 86400


def config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def kind_dir(kind):
    return config_dir() / "cache" / kind


def state_path(kind, session_id):
    safe_id = UNSAFE_ID_CHARACTERS.sub("_", session_id or "nosession")
    return kind_dir(kind) / f"{safe_id}.json"


def read_state(path, empty):
    fresh = copy.deepcopy(empty)
    try:
        stored = json.loads(path.read_text())
    except (OSError, ValueError):
        return fresh
    if not isinstance(stored, dict):
        return fresh
    return {**fresh, **stored}


def write_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(handle, "w") as stream:
            json.dump(state, stream)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


@contextlib.contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(path.with_suffix(".lock"), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        os.close(descriptor)


@contextlib.contextmanager
def update_state(path, empty):
    with locked(path):
        state = read_state(path, empty)
        yield state
        write_state(path, state)


def is_stale(entry, cutoff):
    try:
        return entry.stat().st_mtime < cutoff
    except OSError:
        return False


def remove_entry(entry):
    if entry.is_dir():
        shutil.rmtree(entry, ignore_errors=True)
    else:
        entry.unlink(missing_ok=True)


def prune(kind, max_age_days=7):
    cutoff = time.time() - max_age_days * SECONDS_PER_DAY
    try:
        entries = list(kind_dir(kind).iterdir())
    except OSError:
        return
    for entry in entries:
        if is_stale(entry, cutoff):
            with contextlib.suppress(OSError):
                remove_entry(entry)

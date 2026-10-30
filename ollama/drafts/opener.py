#!/usr/bin/env python3
import argparse
import html
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

DRAFT_ID = re.compile(r"^\d{8}-\d{6}-(pr|review)-[a-z0-9-]{1,60}$")
PAGE_LIFETIME_SECONDS = 60


def parse_options(argv):
    parser = argparse.ArgumentParser(description="Open each new claude-ollama draft in the console")
    parser.add_argument("--drafts", required=True)
    parser.add_argument("--watch-pid", type=int, required=True)
    parser.add_argument("--console-url", required=True)
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--pages", required=True)
    parser.add_argument("--start-console", required=True)
    opener = parser.add_mutually_exclusive_group(required=True)
    opener.add_argument("--open")
    opener.add_argument("--cmux")
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--min-gap", type=float, default=5.0)
    parser.add_argument("--console-wait", type=float, default=300.0)
    return parser.parse_args(argv)


def process_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def ids_ending_in(folder, suffix):
    try:
        names = os.listdir(folder)
    except FileNotFoundError:
        return set()
    stems = (name[: -len(suffix)] for name in names if name.endswith(suffix))
    return {stem for stem in stems if DRAFT_ID.match(stem)}


def draft_ids(folder):
    return ids_ending_in(folder, ".json")


def claim_open_requests(folder):
    requested = ids_ending_in(folder, ".open")
    for draft_id in requested:
        try:
            Path(folder, f"{draft_id}.open").unlink(missing_ok=True)
        except OSError:
            pass
    return requested & draft_ids(folder)


def console_up(console_url):
    try:
        with urllib.request.urlopen(f"{console_url}/health", timeout=2):
            return True
    except urllib.error.HTTPError:
        return True
    except OSError:
        return False


def start_console(options):
    port = str(urlparse(options.console_url).port)
    subprocess.Popen(
        [options.start_console, "ui", "--port", port],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def console_ready(options):
    return console_up(options.console_url) and Path(options.token_file).is_file()


def wait_for_console(options):
    if console_ready(options):
        return True
    start_console(options)
    deadline = time.monotonic() + options.console_wait
    while time.monotonic() < deadline:
        if console_ready(options):
            return True
        time.sleep(0.5)
    return False


def redirect_page(options, draft_id):
    token = Path(options.token_file).read_text().strip()
    target = html.escape(f"{options.console_url}/drafts/{draft_id}?token={token}", quote=True)
    folder = Path(options.pages)
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder.chmod(0o700)
    page = folder / f"{draft_id}.html"
    descriptor = os.open(page, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(f'<!doctype html><meta http-equiv="refresh" content="0;url={target}">\n')
    return page


def remove_old_pages(options):
    cutoff = time.time() - PAGE_LIFETIME_SECONDS
    for page in Path(options.pages).glob("*.html"):
        if page.stat().st_mtime < cutoff:
            page.unlink(missing_ok=True)


def open_command(options, page_url):
    if options.cmux:
        return [options.cmux, "browser", "open-split", page_url, "--focus", "true"]
    return [options.open, page_url]


def open_draft(options, draft_id):
    if not wait_for_console(options):
        print(f"draft opener: the console did not start; open {draft_id} from /drafts", file=sys.stderr)
        return
    page = redirect_page(options, draft_id)
    subprocess.run(open_command(options, page.as_uri()), stdin=subprocess.DEVNULL, check=False)


def watch(options):
    seen = draft_ids(options.drafts)
    pending = None
    last_opened = float("-inf")
    while process_alive(options.watch_pid):
        fresh = draft_ids(options.drafts) - seen
        seen |= fresh
        wanted = fresh | claim_open_requests(options.drafts)
        if wanted:
            pending = max(wanted)
        if pending and time.monotonic() - last_opened >= options.min_gap:
            open_draft(options, pending)
            last_opened = time.monotonic()
            pending = None
        if Path(options.pages).is_dir():
            remove_old_pages(options)
        time.sleep(options.interval)


if __name__ == "__main__":
    watch(parse_options(sys.argv[1:]))

#!/usr/bin/env python3
import argparse
import json
import os
import platform
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "shared"))
from model_server import server_url

DEFAULT_SINCE_MINUTES = 120
COMMAND_LINE_CAP = 80
LOG_TAIL_LINES = 60
INCIDENT_ROWS = 50
HANDOFF_LINES = 20
TOP_DIVERGING = 3
LINE_CHARS = 300
DIFF_CHARS = 120
COMMAND_TIMEOUT_SECONDS = 120
HTTP_TIMEOUT_SECONDS = 5
GIB = 1024 ** 3
REDACTED = "<redacted>"
SECRET_PATTERNS = (
    (re.compile(r"Bearer \S+"), f"Bearer {REDACTED}"),
    (re.compile(r"sk-[A-Za-z0-9_-]{8,}"), REDACTED),
    (re.compile(r"ghp_[A-Za-z0-9]{8,}"), REDACTED),
    (re.compile(r"(?<![A-Za-z0-9+=_-])[A-Za-z0-9+=_-]{40,}"), REDACTED),
)
UNAVAILABLE = "unavailable: "


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Write one pasteable markdown report about a claude-ollama setup.")
    parser.add_argument("--launcher", required=True)
    parser.add_argument("--size", required=True)
    parser.add_argument("--fingerprint-bin", required=True)
    parser.add_argument("--lease-bin", required=True)
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--ollama-url", help=argparse.SUPPRESS)
    parser.add_argument("--server-env", help=argparse.SUPPRESS)
    parser.add_argument("--out")
    parser.add_argument("--since", type=int, default=DEFAULT_SINCE_MINUTES, help="minutes of proxy log to summarise")
    return parser.parse_args(argv)


def unavailable(reason):
    return [UNAVAILABLE + reason]


def is_unavailable(lines):
    return bool(lines) and lines[0].startswith(UNAVAILABLE)


def cap_head(lines, limit):
    if len(lines) <= limit:
        return lines
    return lines[:limit] + [f"... {len(lines) - limit} more lines hidden"]


def cap_tail(lines, limit):
    if len(lines) <= limit:
        return lines
    return [f"... {len(lines) - limit} earlier lines hidden"] + lines[-limit:]


def run_command(argv):
    try:
        completed = subprocess.run(argv, capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS)
    except FileNotFoundError:
        return unavailable(f"{argv[0]} not found")
    except PermissionError:
        return unavailable(f"{argv[0]} is not executable")
    except subprocess.TimeoutExpired:
        return unavailable(f"{' '.join(argv)} timed out after {COMMAND_TIMEOUT_SECONDS} s")
    lines = (completed.stdout + completed.stderr).splitlines()
    if completed.returncode != 0:
        lines.append(f"exit {completed.returncode}")
    return lines or unavailable(f"{' '.join(argv)} printed nothing")


def read_lines(path):
    try:
        return Path(path).read_text(errors="replace").splitlines()
    except OSError as error:
        return None, f"{path}: {error.strerror or error}"
    except ValueError as error:
        return None, f"{path}: {error}"


def file_tail(path, limit):
    lines = read_lines(path)
    if isinstance(lines, tuple):
        return unavailable(lines[1])
    return cap_tail(lines, limit) or unavailable(f"{path} is empty")


def doctor_section(options):
    return cap_head(run_command([options.launcher, "doctor", options.size]), COMMAND_LINE_CAP)


def print_config_section(options):
    return cap_head(run_command([options.launcher, "--print-config", options.size]), COMMAND_LINE_CAP)


def fingerprint_section(options):
    return cap_head(run_command([options.fingerprint_bin]), COMMAND_LINE_CAP)


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT_SECONDS) as response:
        return json.loads(response.read())


def props_lines(props):
    return [f"{key}: {props[key]}" for key in ("build_info", "role", "max_instances") if key in props]


def model_line(entry):
    status = (entry.get("status") or {}).get("value", "?")
    meta = entry.get("meta") or {}
    parts = [f"n_ctx {meta['n_ctx']}" if meta.get("n_ctx") else None,
             f"{meta['size'] / GIB:.1f} GiB" if isinstance(meta.get("size"), (int, float)) and meta["size"] else None]
    details = ", ".join(part for part in parts if part)
    line = f"{entry.get('id', '?')} {status}"
    return f"{line} ({details})" if details else line


def server_section(options):
    url = server_url().rstrip("/")
    try:
        props = fetch_json(url + "/props")
        models = fetch_json(url + "/models").get("data") or []
    except (OSError, urllib.error.URLError, ValueError, AttributeError) as error:
        return [f"server: {url}"] + unavailable(f"{url}: {getattr(error, 'reason', error)}")
    presets = [entry for entry in models if entry.get("source", "preset") == "preset"]
    lines = [f"server: {url}"] + [line.replace("build_info:", "build:") for line in props_lines(props)]
    return lines + ["models:"] + ([model_line(entry) for entry in presets] or ["no preset listed"])


def lease_rung(lines):
    for line in lines:
        words = line.split()
        if len(words) >= 8 and words[0] == "live" and words[1] == "session" and words[6] == "rung":
            return words[7]
    return "none"


def lease_section(options):
    lines = run_command([options.lease_bin, "holders"])
    if is_unavailable(lines):
        return lines
    holders = [line for line in lines if line and not line.startswith("exit ")]
    return (holders or ["no lease holders"]) + [f"rung: {lease_rung(holders)}"]


def json_rows(path):
    rows = []
    for line in Path(path).read_text(errors="replace").splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def incident_rows(state_dir):
    current = Path(state_dir) / "incidents" / "current"
    try:
        incidents_path = current.read_text().strip()
    except OSError:
        return None, f"{current} missing (no session has run)"
    try:
        rows = json_rows(incidents_path)
    except OSError as error:
        return None, f"{incidents_path}: {error.strerror or error}"
    return [row for row in rows if "kind" not in row], incidents_path


def cause_counts(rows):
    counts = Counter(row.get("cause", "unknown") for row in rows)
    return ", ".join(f"{cause}: {count}" for cause, count in sorted(counts.items()))


def incidents_section(options):
    rows, detail = incident_rows(options.state_dir)
    if rows is None:
        return unavailable(detail)
    if not rows:
        return [f"no incident rows in {detail}"]
    shown = [json.dumps(row, separators=(", ", ": ")) for row in rows[-INCIDENT_ROWS:]]
    return [f"rows: {len(rows)} in {detail}", f"counts: {cause_counts(rows)}"] + shown


def parse_ts(text):
    try:
        return datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    except ValueError:
        return None


def proxy_log_path(options):
    for folder in (options.state_dir, options.session_dir):
        candidate = Path(folder) / "proxy" / "requests.jsonl"
        if candidate.is_file():
            return candidate
    return None


def rows_within(rows, minutes):
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    kept = []
    for row in rows:
        stamp = parse_ts(row.get("ts"))
        if stamp is not None and stamp.tzinfo is not None and stamp >= cutoff:
            kept.append(row)
    return kept


def kept_prefix(row):
    diverged_at = row.get("diverged_at")
    if diverged_at is None:
        return True
    return diverged_at == f"message:{int(row.get('sections', 0)) - 1}"


def diverging_lines(rows):
    counts = Counter(row["diverged_at"] for row in rows if row.get("diverged_at") is not None and not kept_prefix(row))
    lines = []
    for name, count in counts.most_common(TOP_DIVERGING):
        last = next(row for row in reversed(rows) if row.get("diverged_at") == name)
        diff = (last.get("diff") or "")[:DIFF_CHARS]
        lines.append(f"- {name}: {count} requests, offset {last.get('offset')}, last diff: {diff!r}")
    return lines


def record_dir_lines(session_dir):
    folder = Path(session_dir) / "proxy" / "record"
    if not folder.is_dir():
        return []
    count = len(list(folder.glob("*.json")))
    return [f"record dir: {folder} ({count} requests)"]


def proxy_stats(rows):
    kept = sum(1 for row in rows if kept_prefix(row))
    percent = round(100 * kept / len(rows)) if rows else 0
    return {"requests": len(rows), "kept": kept, "percent": percent}


def proxy_section(options):
    path = proxy_log_path(options)
    if path is None:
        return unavailable("no proxy log under the console state dir or the session dir") + record_dir_lines(options.session_dir)
    try:
        rows = rows_within(json_rows(path), options.since)
    except OSError as error:
        return unavailable(f"{path}: {error.strerror or error}")
    if not rows:
        return [f"no requests in the last {options.since} min ({path})"] + record_dir_lines(options.session_dir)
    stats = proxy_stats(rows)
    lines = [
        f"log: {path}",
        f"requests: {stats['requests']}",
        f"prefix hit rate: {stats['percent']}% ({stats['kept']} of {stats['requests']} kept every section but the newest message)",
    ]
    diverging = diverging_lines(rows)
    if diverging:
        lines.append("top diverging sections:")
        lines.extend(diverging)
    return lines + record_dir_lines(options.session_dir)


def launcher_log_section(options):
    return file_tail(Path(options.state_dir) / "launcher.log", LOG_TAIL_LINES)


def server_log_section(options):
    lines = run_command([options.launcher, "logs", "--path"])
    if is_unavailable(lines) or lines[-1].startswith("exit "):
        return unavailable("no llama-server log found (" + "; ".join(lines) + ")")
    return file_tail(lines[0].strip(), LOG_TAIL_LINES)


def handoff_dir():
    try:
        completed = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True, timeout=COMMAND_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"git: {error}"
    if completed.returncode != 0:
        return None, f"{os.getcwd()} is not inside a git repository"
    return Path(completed.stdout.strip()).resolve() / "handoff", None


def handoff_section(options):
    folder, reason = handoff_dir()
    if folder is None:
        return unavailable(reason)
    notes = [path for path in folder.glob("*") if path.is_file()] if folder.is_dir() else []
    if not notes:
        return unavailable(f"no handoff note in {folder}")
    newest = max(notes, key=lambda path: path.stat().st_mtime)
    lines = read_lines(newest)
    if isinstance(lines, tuple):
        return unavailable(lines[1])
    return [f"note: {newest}"] + cap_head(lines, HANDOFF_LINES)


def darwin_memory():
    total = int(subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=10, check=True).stdout.strip())
    stats = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=10, check=True).stdout
    page_size = int(re.search(r"page size of (\d+) bytes", stats).group(1))
    pages = {}
    for line in stats.splitlines():
        match = re.match(r"(Pages (?:free|inactive|speculative)):\s+(\d+)\.", line)
        if match:
            pages[match.group(1)] = int(match.group(2))
    return total, sum(pages.values()) * page_size


def linux_memory():
    fields = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, _, rest = line.partition(":")
        fields[key] = int(rest.split()[0]) * 1024
    return fields["MemTotal"], fields["MemAvailable"]


def memory_section(options):
    try:
        total, free = darwin_memory() if platform.system() == "Darwin" else linux_memory()
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, AttributeError) as error:
        return unavailable(f"cannot read memory on {platform.system()}: {error}")
    return [f"total: {total / GIB:.1f} GiB", f"free: {free / GIB:.1f} GiB"]


def sections(options):
    return [
        ("Doctor", doctor_section(options)),
        ("Print config", print_config_section(options)),
        ("Sync fingerprint", fingerprint_section(options)),
        ("Server and models", server_section(options)),
        ("Lease holders and rung", lease_section(options)),
        (f"Incidents (last {INCIDENT_ROWS} rows)", incidents_section(options)),
        (f"Messages proxy (last {options.since} min)", proxy_section(options)),
        ("Launcher log tail", launcher_log_section(options)),
        ("Server log tail", server_log_section(options)),
        ("Newest handoff note", handoff_section(options)),
        ("Free memory", memory_section(options)),
    ]


def home_aliases():
    home = os.environ.get("HOME")
    if not home:
        return []
    aliases = {home.rstrip("/"), os.path.realpath(home)}
    return sorted((alias for alias in aliases if alias and alias != "/"), key=len, reverse=True)


def redact(text, aliases):
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    for alias in aliases:
        text = text.replace(alias, "~")
    return text


def clean_line(line, aliases):
    cleaned = redact(line, aliases)
    return cleaned if len(cleaned) <= LINE_CHARS else cleaned[:LINE_CHARS] + "..."


def render(options, report_sections, aliases):
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    lines = ["# claude-ollama rescue", "", f"generated: {stamp} size: {options.size} host: {platform.node()} platform: {platform.platform()}", ""]
    for title, body in report_sections:
        lines.extend([f"## {title}", "", "```text"])
        lines.extend(clean_line(line, aliases) for line in body)
        lines.extend(["```", ""])
    return "\n".join(lines)


def section_body(report_sections, prefix):
    return next(body for title, body in report_sections if title.startswith(prefix))


def doctor_summary(body):
    if is_unavailable(body):
        return "doctor: unavailable"
    fails = sum(1 for line in body if line.startswith("fail "))
    return "doctor: ok" if fails == 0 else f"doctor: {fails} fail line(s)"


def lease_summary(body):
    if is_unavailable(body):
        return "lease: unavailable"
    session = next((line for line in body if line.startswith("live session ")), None)
    return f"lease: {session[5:]}" if session else "lease: no session holder"


def incidents_summary(body):
    if is_unavailable(body):
        return "incidents: unavailable"
    if not body[0].startswith("rows: "):
        return "incidents: none"
    count = body[0].split()[1]
    return f"incidents: {count} rows ({body[1][len('counts: '):]})"


def proxy_summary(body, since):
    if is_unavailable(body):
        return "proxy: unavailable"
    requests = next((line for line in body if line.startswith("requests: ")), None)
    if requests is None:
        return f"proxy: no requests in last {since} min"
    rate = next(line for line in body if line.startswith("prefix hit rate: ")).split("(")[0].strip()
    return f"proxy: {requests[len('requests: '):]} requests in last {since} min, {rate}"


def memory_summary(body):
    if is_unavailable(body):
        return "memory: unavailable"
    return f"memory: {body[1][len('free: '):]} free of {body[0][len('total: '):]}"


def summary(options, report_sections):
    return [
        doctor_summary(section_body(report_sections, "Doctor")),
        lease_summary(section_body(report_sections, "Lease")),
        incidents_summary(section_body(report_sections, "Incidents")),
        proxy_summary(section_body(report_sections, "Messages proxy"), options.since),
        memory_summary(section_body(report_sections, "Free memory")),
    ]


def default_out(session_dir):
    folder = Path(session_dir) / "rescue"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder.chmod(0o700)
    return folder / datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ.md")


def write_private(path, text):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(text)
    os.chmod(path, 0o600)


def main(argv):
    options = parse_args(argv)
    aliases = home_aliases()
    report_sections = sections(options)
    text = render(options, report_sections, aliases)
    try:
        out = Path(options.out) if options.out else default_out(options.session_dir)
        write_private(out, text)
    except OSError as error:
        print(f"rescue: cannot write {options.out or options.session_dir}: {error.strerror or error}", file=sys.stderr)
        return 1
    print(redact(str(out), aliases))
    for line in summary(options, report_sections):
        print(clean_line(line, aliases))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

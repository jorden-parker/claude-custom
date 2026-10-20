#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from pathlib import Path

OUTPUT_LINE_LIMIT = 40
TAIL_LINES = 15
MAX_SIGNAL_LINES = 20
MAX_LINE_CHARS = 300
MAX_FINDINGS = 20
SIGNAL = re.compile(r"error|fail|panic|traceback|exception|fatal|assert|not ok", re.IGNORECASE)
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
JS_PROJECT_MARKERS = ("package.json", "tsconfig.json")
JS_FILE = re.compile(r"\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$")
BASE_BRANCHES = ("main", "master", "HEAD")
FINDING_NAME_FIELDS = ("export_name", "member_name", "name", "package_name", "message")
FALLOW_ADVICE = ("Fallow found problems in your changes. Run `npx fallow explain <issue-type>` for any "
                 "finding you don't understand. Remove dead code instead of suppressing it.")
FALLOW_UNLISTED = "{file}: fallow failed without a finding this hook can list; rerun it without --format json"
VERIFY_SCRIPT = Path(".claude") / "verify"
OPT_OUT_FILE = Path(".claude") / "no-verify"
EDITS_DIR = Path(os.environ.get("STOP_VERIFY_STATE_DIR") or Path.home() / ".cache" / "claude-custom" / "edited-files")


def edits_log(event):
    return EDITS_DIR / Path(event.get("session_id") or "unknown").name


def record_edit(event):
    path = event.get("tool_input", {}).get("file_path")
    if not path:
        return
    EDITS_DIR.mkdir(parents=True, exist_ok=True)
    with edits_log(event).open("a") as log:
        log.write(path + "\n")


def relative_to_root(path, root):
    try:
        return str(Path(path).resolve().relative_to(root))
    except ValueError:
        return None


def edited_files(event, root):
    log = edits_log(event)
    if not log.is_file():
        return []
    relative = (relative_to_root(path, root) for path in log.read_text().splitlines())
    return sorted({path for path in relative if path})


def project_root(cwd):
    result = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return Path(result.stdout.strip() if result.returncode == 0 else cwd).resolve()


def unique(lines):
    return list(dict.fromkeys(lines))


def clip_line(line):
    if len(line) <= MAX_LINE_CHARS:
        return line
    return f"{line[:MAX_LINE_CHARS]} … [{len(line) - MAX_LINE_CHARS} chars hidden]"


def capped(lines, limit, noun):
    if len(lines) <= limit:
        return lines
    return lines[:limit] + [f"[{len(lines) - limit} more {noun} hidden]"]


def failure_excerpt(text):
    lines = [line for line in ANSI_ESCAPE.sub("", text).splitlines() if line.strip()]
    if len(lines) <= OUTPUT_LINE_LIMIT:
        return unique(lines)
    earlier, tail = lines[:-TAIL_LINES], lines[-TAIL_LINES:]
    signals = unique(line for line in earlier if SIGNAL.search(line))[:MAX_SIGNAL_LINES]
    return signals + [f"[{len(earlier) - len(signals)} more lines hidden]"] + tail


def run_failing(command, root):
    result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode == 0:
        return None
    return "\n".join([f"$ {' '.join(command)}", *map(clip_line, failure_excerpt(result.stdout))])


def base_branch(root):
    for branch in BASE_BRANCHES:
        if subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", "-q", branch], capture_output=True).returncode == 0:
            return branch
    return None


def fallow_command(base, file):
    analysis = ["audit", "--base", base] if base else ["--fail-on-issues"]
    return ["npx", "--yes", "fallow", *analysis, "--format", "json", file]


def fallow_commands(root, files):
    base = base_branch(root)
    return [fallow_command(base, file)
            for file in files if JS_FILE.search(file) and (root / file).is_file()]


def is_new_finding(finding):
    return isinstance(finding, dict) and "path" in finding and finding.get("introduced", True)


def issue_type(key, finding):
    parts = str(finding.get("finding_id", "")).split(":")
    return parts[1] if len(parts) == 3 else key


def finding_name(finding):
    return next((str(finding[field]) for field in FINDING_NAME_FIELDS if finding.get(field)), "")


def finding_location(finding):
    line = finding.get("line")
    return f"{finding['path']}:{line}" if line else str(finding["path"])


def dead_code_lines(report):
    section = report.get("dead_code") or report.get("check") or {}
    for key, findings in section.items():
        if key == "workspace_diagnostics" or not isinstance(findings, list):
            continue
        for finding in filter(is_new_finding, findings):
            yield f"{issue_type(key, finding)} {finding_location(finding)} {finding_name(finding)}".rstrip()


def complexity_lines(report):
    section = report.get("complexity") or report.get("health") or {}
    for finding in filter(is_new_finding, section.get("findings") or []):
        yield (f"high-complexity {finding_location(finding)} {finding_name(finding)} "
               f"cyclomatic={finding.get('cyclomatic')} cognitive={finding.get('cognitive')}")


def clone_instance(instance):
    return f"{instance.get('file')}:{instance.get('start_line')}-{instance.get('end_line')}"


def duplication_lines(report):
    section = report.get("duplication") or report.get("dupes") or {}
    for group in section.get("clone_groups") or []:
        yield "duplication " + " = ".join(map(clone_instance, group.get("instances", [])))


def finding_lines(report):
    return [*dead_code_lines(report), *complexity_lines(report), *duplication_lines(report)]


def parsed_report(text):
    try:
        report = json.loads(text)
    except ValueError:
        return None
    return report if isinstance(report, dict) and not report.get("error") else None


def fallow_findings(command, root):
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    report = parsed_report(result.stdout) if result.returncode else None
    if report is None:
        return []
    return finding_lines(report) or [FALLOW_UNLISTED.format(file=command[-1])]


def fallow_failures(root, files):
    if not any((root / marker).exists() for marker in JS_PROJECT_MARKERS):
        return []
    findings = unique(line for command in fallow_commands(root, files) for line in fallow_findings(command, root))
    if not findings:
        return []
    listed = "\n".join("  " + clip_line(line) for line in capped(findings, MAX_FINDINGS, "findings"))
    return [f"{FALLOW_ADVICE}\n{listed}"]


def makefile_has_test_target(root):
    makefile = root / "Makefile"
    return makefile.is_file() and re.search(r"^test\s*:", makefile.read_text(), re.MULTILINE) is not None


def package_json_has_test_script(root):
    package = root / "package.json"
    if not package.is_file():
        return False
    try:
        return "test" in json.loads(package.read_text()).get("scripts", {})
    except ValueError:
        return False


def discovered_test_command(root):
    if makefile_has_test_target(root):
        return ["make", "test"]
    if (root / "go.mod").is_file():
        return ["go", "test", "./..."]
    if package_json_has_test_script(root):
        return ["pnpm", "test"]
    return None


def test_command(root, files):
    script = root / VERIFY_SCRIPT
    if script.is_file():
        return [str(script), *files]
    if (root / OPT_OUT_FILE).exists():
        return None
    return discovered_test_command(root)


def verify_failures(root, files):
    command = test_command(root, files)
    if command is None:
        return []
    failure = run_failing(command, root)
    return [failure] if failure else []


def verify_edits(event):
    root = project_root(event.get("cwd", "."))
    files = edited_files(event, root)
    if not files:
        return
    failures = fallow_failures(root, files) + verify_failures(root, files)
    if failures:
        print("Not done yet: fix these, then finish.\n\n" + "\n\n".join(failures), file=sys.stderr)
        sys.exit(2)
    edits_log(event).unlink(missing_ok=True)


def main():
    event = json.load(sys.stdin)
    if event.get("hook_event_name") == "PostToolUse":
        record_edit(event)
    elif not event.get("stop_hook_active"):
        verify_edits(event)


main()

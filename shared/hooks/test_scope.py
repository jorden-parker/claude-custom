import re
import sys
from pathlib import Path

CODE_SUFFIXES = {".go", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".sh", ".bash", ".zsh"}
PACKAGE_SUFFIXES = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"}
TEST_NAME = re.compile(r"(^|[._-])(test|tests|spec)([._-]|$)")
TEST_DIRS = {"test", "tests", "__tests__", "testdata", "fixtures", "eval", ".claude"}
RUNNABLE_TEST_DIRS = TEST_DIRS - {".claude"}
VITEST_SUFFIXES = (".ts", ".tsx", ".js", ".jsx", ".mts", ".mjs")
PROJECT_MARKERS = (".git", ".claude")


def first_line_of_file(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.readline()
    except OSError:
        return ""


def is_code(path, tool_input, tool_name):
    if path.suffix in CODE_SUFFIXES:
        return True
    if path.suffix:
        return False
    first_line = (tool_input.get("content") or "")[:120] if tool_name == "Write" else first_line_of_file(path)
    return first_line.startswith("#!")


def stem_of(path):
    return path.name.split(".")[0] if path.suffix else path.name


def has_test_name(path):
    return bool(TEST_NAME.search(stem_of(path))) or ".test." in path.name or ".spec." in path.name


def is_test(path):
    return has_test_name(path) or any(part in TEST_DIRS for part in path.parts)


def is_runnable_test(path):
    return has_test_name(path) or any(part in RUNNABLE_TEST_DIRS for part in path.parts)


def within(path, root):
    return path == root or root in path.parents


def nearest_dir_with(path, marker, root=None):
    for parent in path.parents:
        if root is not None and not within(parent, root):
            return None
        if (parent / marker).exists():
            return parent
    return None


def scope_of(path):
    if path.suffix in PACKAGE_SUFFIXES:
        root = nearest_dir_with(path, "package.json")
        if root is not None:
            return str(root)
    return str(path.parent)


def expected_test_name(path):
    stem = stem_of(path)
    if path.suffix == ".go":
        return f"{stem}_test.go"
    if path.suffix in PACKAGE_SUFFIXES:
        return f"{stem}.test{path.suffix}"
    return f"{stem}.test.sh"


def expected_test_path(path):
    return path.parent / expected_test_name(path)


def project_root(path, cwd):
    for marker in PROJECT_MARKERS:
        root = nearest_dir_with(path, marker, cwd)
        if root is not None:
            return root
    return cwd


def first_existing(candidates):
    return next((candidate for candidate in candidates if candidate.is_file()), None)


def go_test_file(path):
    beside = path.parent / f"{stem_of(path)}_test.go"
    if beside.is_file():
        return beside
    return first_existing(sorted(path.parent.glob("*_test.go")))


def vitest_file(path):
    stem = stem_of(path)
    names = [f"{stem}.{kind}{suffix}" for kind in ("test", "spec") for suffix in (path.suffix, *VITEST_SUFFIXES)]
    folders = (path.parent, path.parent / "__tests__")
    return first_existing(folder / name for folder in folders for name in names)


def pytest_file(path):
    stem = stem_of(path)
    return first_existing(path.parent / name for name in (f"test_{stem}.py", f"{stem}_test.py"))


def shell_test_file(path):
    return first_existing([path.parent / f"{stem_of(path)}.test.sh"])


KIND_FINDERS = {".go": go_test_file, ".py": pytest_file, **{suffix: vitest_file for suffix in PACKAGE_SUFFIXES}}


def test_file_for(path):
    if is_runnable_test(path) and path.is_file():
        return path
    finder = KIND_FINDERS.get(path.suffix)
    found = finder(path) if finder else None
    return found or shell_test_file(path)


def relative_to(path, base):
    try:
        return str(path.relative_to(base))
    except ValueError:
        return str(path)


def shown_command(words, run_dir, cwd):
    rendered = " ".join(words)
    if run_dir == cwd:
        return rendered
    return f"cd {relative_to(run_dir, cwd)} && {rendered}"


def go_command(test, cwd):
    module_root = nearest_dir_with(test, "go.mod", cwd) or test.parent
    package = relative_to(test.parent, module_root)
    words = ["go", "test", "./" + package if package != "." else "."]
    return {"test": test, "argv": words, "cwd": module_root, "display": shown_command(words, module_root, cwd)}


def vitest_command(test, cwd):
    package_root = nearest_dir_with(test, "package.json", cwd) or test.parent
    run_dir = project_root(test, cwd)
    words = ["pnpm", "-C", relative_to(package_root, run_dir), "exec", "vitest", "run", relative_to(test, package_root)]
    return {"test": test, "argv": words, "cwd": run_dir, "display": shown_command(words, run_dir, cwd)}


def pytest_command(test, cwd):
    run_dir = project_root(test, cwd)
    words = ["pytest", relative_to(test, run_dir)]
    return {"test": test, "argv": words, "cwd": run_dir, "display": shown_command(words, run_dir, cwd)}


def shell_command(test, cwd):
    run_dir = project_root(test, cwd)
    shown = relative_to(test, run_dir)
    words = [shown if shown.startswith("/") else "./" + shown]
    return {"test": test, "argv": [str(test)], "cwd": run_dir, "display": shown_command(words, run_dir, cwd)}


def verify_command(path, cwd):
    root = nearest_dir_with(path, Path(".claude") / "verify", cwd)
    if root is None:
        return None
    verify = root / ".claude" / "verify"
    if verify == path:
        return None
    words = [".claude/verify", relative_to(path, root)]
    return {"test": verify, "argv": [str(verify), str(path)], "cwd": root, "display": shown_command(words, root, cwd)}


def command_for(test, cwd):
    if test.name.endswith("_test.go"):
        return go_command(test, cwd)
    if test.suffix == ".py":
        return pytest_command(test, cwd)
    if test.suffix in VITEST_SUFFIXES:
        return vitest_command(test, cwd)
    return shell_command(test, cwd)


def resolve_test(path, cwd):
    test = test_file_for(path)
    if test is not None:
        return command_for(test, cwd)
    return verify_command(path, cwd)


def main(arguments):
    if arguments[:1] == ["--expected"]:
        print(expected_test_path(Path(arguments[1])))
        return
    path = Path(arguments[0])
    cwd = Path(arguments[1]) if len(arguments) > 1 else Path.cwd()
    resolved = resolve_test(path, cwd)
    if resolved is not None:
        print(f"{resolved['test']}\t{resolved['display']}")


if __name__ == "__main__":
    main(sys.argv[1:])

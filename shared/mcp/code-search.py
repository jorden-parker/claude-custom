#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

OLLAMA_URL = os.environ.get("CODE_SEARCH_OLLAMA_URL", "http://localhost:11434")
EMBED_MODEL = os.environ.get("CODE_SEARCH_MODEL") or "qwen3-embedding:0.6b"
DIMENSIONS = 256
CHUNK_LINES = 40
CHUNK_STEP = 30
MAX_CHUNK_CHARS = 2000
MAX_FILE_BYTES = 200_000
EMBED_BATCH = 32
DEFAULT_LIMIT = 8
MAX_LIMIT = 20
PREVIEW_CHARS = 100
QUERY_INSTRUCTION = "Instruct: Given a code search query, retrieve relevant code snippets\nQuery: "
SKIPPED_NAMES = {
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "Cargo.lock",
    "poetry.lock",
    "Gemfile.lock",
    "composer.lock",
    "go.sum",
}
SKIPPED_SUFFIXES = (".min.js", ".map", ".svg", ".png", ".jpg", ".gif", ".ico", ".pdf")

TOOL = {
    "name": "semantic_search",
    "description": (
        "Always call this first to find code in the current git repo, before any Read. "
        "Returns file:start-end line ranges with a score and a one-line preview; then "
        "Read only those ranges with offset/limit. For exact identifiers use "
        "`git grep -n` in Bash."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "What the code does, in plain words"},
            "limit": {"type": "integer", "description": f"Results to return (default {DEFAULT_LIMIT}, max {MAX_LIMIT})"},
        },
        "required": ["query"],
    },
}


class SearchError(Exception):
    pass


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=True).stdout


def repo_root():
    try:
        return Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
    except subprocess.CalledProcessError as error:
        raise SearchError("semantic_search only works inside a git repository.") from error


def index_path(root):
    git_dir = Path(git(root, "rev-parse", "--absolute-git-dir").strip())
    return git_dir / "code-search" / "index.json"


def is_searchable(path):
    return path.name not in SKIPPED_NAMES and not path.name.endswith(SKIPPED_SUFFIXES)


def candidate_files(root):
    listed = git(root, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    return sorted({name for name in listed if is_searchable(Path(name)) and (root / name).is_file()})


def read_text(path):
    data = path.read_bytes()
    if len(data) > MAX_FILE_BYTES or b"\0" in data[:8192]:
        return None
    return data.decode("utf-8", errors="replace")


def chunk_ranges(line_count):
    starts = range(0, max(line_count - CHUNK_LINES, 0) + 1, CHUNK_STEP)
    ranges = [(start, min(start + CHUNK_LINES, line_count)) for start in starts]
    if ranges and ranges[-1][1] < line_count:
        ranges.append((ranges[-1][0] + CHUNK_STEP, line_count))
    return ranges


def file_chunks(name, text):
    lines = text.splitlines()
    return [
        {"start": start + 1, "end": end, "text": f"{name}\n" + "\n".join(lines[start:end])[:MAX_CHUNK_CHARS]}
        for start, end in chunk_ranges(len(lines))
        if any(line.strip() for line in lines[start:end])
    ]


def normalized(vector):
    head = vector[:DIMENSIONS]
    norm = sum(value * value for value in head) ** 0.5 or 1.0
    return [round(value / norm, 5) for value in head]


def embed(texts):
    vectors = []
    for start in range(0, len(texts), EMBED_BATCH):
        vectors.extend(embed_batch(texts[start : start + EMBED_BATCH]))
    return vectors


def embed_batch(texts):
    request = urllib.request.Request(
        f"{OLLAMA_URL}/api/embed",
        data=json.dumps({"model": EMBED_MODEL, "input": texts}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return [normalized(vector) for vector in json.load(response)["embeddings"]]
    except (urllib.error.URLError, OSError, KeyError, ValueError) as error:
        raise SearchError(
            f"Embedding request to {OLLAMA_URL} failed ({error}). Check that `ollama serve` "
            f"is running and run `ollama pull {EMBED_MODEL}` (or run `claude-ollama` and pick "
            "'Set up embedding model'). Use `git grep -n` until then."
        ) from error


def load_index(path):
    try:
        index = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return index.get("files", {}) if index.get("model") == EMBED_MODEL else {}


def save_index(path, files):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"model": EMBED_MODEL, "files": files}))
    temporary.replace(path)


def indexed_file(name, text):
    chunks = file_chunks(name, text)
    vectors = embed([chunk["text"] for chunk in chunks])
    return [
        {"start": chunk["start"], "end": chunk["end"], "preview": preview(chunk["text"]), "vector": vector}
        for chunk, vector in zip(chunks, vectors)
    ]


def preview(chunk_text):
    body = chunk_text.split("\n")[1:]
    meaningful = (line.strip() for line in body if line.strip() and not line.startswith("#!"))
    return next((line[:PREVIEW_CHARS] for line in meaningful), "")


def refreshed_index(root, files):
    current = {}
    for name in candidate_files(root):
        text = read_text(root / name)
        if text is None:
            continue
        digest = hashlib.sha1(text.encode("utf-8")).hexdigest()
        known = files.get(name)
        if known and known["hash"] == digest:
            current[name] = known
        else:
            current[name] = {"hash": digest, "chunks": indexed_file(name, text)}
    return current


def ranked_chunks(files, query_vector):
    scored = [
        (sum(a * b for a, b in zip(query_vector, chunk["vector"])), name, chunk)
        for name, entry in files.items()
        for chunk in entry["chunks"]
    ]
    return sorted(scored, key=lambda item: item[0], reverse=True)


def result_line(score, name, chunk):
    return f"{name}:{chunk['start']}-{chunk['end']}  {score:.2f}  {chunk['preview']}"


def refreshed_files(root):
    path = index_path(root)
    files = refreshed_index(root, load_index(path))
    save_index(path, files)
    return files


def build_index():
    return len(refreshed_files(repo_root()))


def search(query, limit):
    files = refreshed_files(repo_root())
    query_vector = embed([QUERY_INSTRUCTION + query])[0]
    lines = [result_line(*item) for item in ranked_chunks(files, query_vector)[:limit]]
    return "\n".join(lines) or "No indexed code yet."


def clamped_limit(value):
    try:
        return max(1, min(int(value), MAX_LIMIT))
    except (TypeError, ValueError):
        return DEFAULT_LIMIT


def call_tool(params):
    if params.get("name") != TOOL["name"]:
        return tool_result(f"Unknown tool: {params.get('name')}", True)
    arguments = params.get("arguments") or {}
    try:
        return tool_result(search(str(arguments.get("query", "")), clamped_limit(arguments.get("limit", DEFAULT_LIMIT))), False)
    except SearchError as error:
        return tool_result(str(error), True)


def tool_result(text, is_error):
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def initialize_result(params):
    return {
        "protocolVersion": params.get("protocolVersion", "2025-06-18"),
        "capabilities": {"tools": {}},
        "serverInfo": {"name": "code-search", "version": "1.0.0"},
    }


HANDLERS = {
    "initialize": initialize_result,
    "ping": lambda params: {},
    "tools/list": lambda params: {"tools": [TOOL]},
    "tools/call": call_tool,
}


def response(message):
    handler = HANDLERS.get(message.get("method"))
    if handler is None:
        return {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Method not found"}}
    return {"jsonrpc": "2.0", "id": message["id"], "result": handler(message.get("params") or {})}


def main():
    if sys.argv[1:] == ["--index"]:
        try:
            print(f"indexed {build_index()} files")
        except SearchError as error:
            print(error, file=sys.stderr)
            sys.exit(1)
        return
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        if "id" in message:
            print(json.dumps(response(message)), flush=True)


main()

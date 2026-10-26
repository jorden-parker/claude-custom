#!/usr/bin/env python3
import hashlib
import heapq
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path


def ollama_url():
    url = os.environ.get("CODE_SEARCH_OLLAMA_URL") or os.environ.get("OLLAMA_HOST") or "http://localhost:11434"
    return url if url.startswith(("http://", "https://")) else f"http://{url}"


OLLAMA_URL = ollama_url()
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
INDEX_VERSION = 2
EMBED_KEEP_ALIVE = "30m"
CAMEL_BOUNDARY = re.compile(r"([a-z0-9])([A-Z])")
ACRONYM_BOUNDARY = re.compile(r"([A-Z]+)([A-Z][a-z])")
WORD = re.compile(r"[a-z]{2,}")
STOP_WORDS = {
    "the", "is", "are", "was", "be", "of", "in", "to", "an", "and", "or", "for", "on", "at", "by",
    "with", "from", "how", "what", "where", "which", "when", "who", "why", "does", "do", "did",
    "that", "this", "it", "its", "as", "we", "you", "our", "your", "into", "not", "no", "any",
    "all", "some", "there", "here", "than", "then", "so", "if",
}
QUERY_SUFFIXES = ("ing", "ed", "es", "s")
VARIANT_SUFFIXES = ("", "s", "es", "ed", "ing", "er", "ers", "e", "d", "ion", "ions")
BM25_K1 = 1.2
BM25_B = 0.75
CANDIDATES = 50
RRF_K = 60
PS_TIMEOUT = 1
EMBED_ALLOWED = os.environ.get("CODE_SEARCH_EMBED") == "1"
WORDS_ONLY_NOTE = "words only: the embedding model is not loaded, so synonyms will not match; use the code's own terms."

TOOL = {
    "name": "semantic_search",
    "description": (
        "Always call this first to find code in the current git repo, before any Read. "
        "Use the words the code itself would use (identifiers are split into words; "
        "English synonyms match only when the embedding model is loaded). Returns "
        "file:start-end line ranges with a relative score and a one-line preview; then "
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


def is_regular_file(path):
    return path.is_file() and not path.is_symlink()


def candidate_files(root):
    listed = git(root, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    return sorted({name for name in listed if is_searchable(Path(name)) and is_regular_file(root / name)})


def read_text(path):
    try:
        with path.open("rb") as handle:
            data = handle.read(MAX_FILE_BYTES + 1)
    except OSError:
        return None
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


def failure_reason(error):
    if not isinstance(error, urllib.error.HTTPError):
        return str(error)
    try:
        return f"{error}: {json.load(error)['error']}"
    except (OSError, KeyError, TypeError, ValueError):
        return str(error)


def embed(texts):
    vectors = []
    for start in range(0, len(texts), EMBED_BATCH):
        vectors.extend(embed_batch(texts[start : start + EMBED_BATCH]))
    return vectors


def embed_batch(texts):
    request = urllib.request.Request(
        f"{OLLAMA_URL}/api/embed",
        data=json.dumps({"model": EMBED_MODEL, "input": texts, "keep_alive": EMBED_KEEP_ALIVE}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return [normalized(vector) for vector in json.load(response)["embeddings"]]
    except (urllib.error.URLError, OSError, KeyError, ValueError) as error:
        raise SearchError(
            f"Embedding request to {OLLAMA_URL} failed ({failure_reason(error)}). Check that `ollama serve` "
            f"is running and run `ollama pull {EMBED_MODEL}` (or run `claude-ollama` and pick "
            "'Set up embedding model'). Use `git grep -n` until then."
        ) from error


def load_index(path):
    try:
        index = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    if index.get("version") != INDEX_VERSION or index.get("model") != EMBED_MODEL:
        return {}
    return index.get("files", {})


def save_index(path, files):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = json.dumps({"version": INDEX_VERSION, "model": EMBED_MODEL, "files": files})
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    with os.fdopen(descriptor, "w") as handle:
        handle.write(payload)
    os.replace(temporary, path)


def words(text):
    spaced = ACRONYM_BOUNDARY.sub(r"\1 \2", CAMEL_BOUNDARY.sub(r"\1 \2", text))
    return WORD.findall(spaced.lower())


def stem(word):
    for suffix in QUERY_SUFFIXES:
        if word.endswith(suffix) and len(word) - len(suffix) >= 3 and not word.endswith("ss"):
            word = word[: -len(suffix)]
            break
    if len(word) >= 4 and word[-1] == word[-2] and word[-1] not in "aeiou":
        word = word[:-1]
    return word


def variants(stem_word):
    forms = {stem_word + suffix for suffix in VARIANT_SUFFIXES}
    forms |= {stem_word + stem_word[-1] + suffix for suffix in ("ed", "ing", "er", "ers")}
    return forms


def worded_chunk(chunk):
    terms = Counter(words(chunk["text"]))
    return {
        "start": chunk["start"],
        "end": chunk["end"],
        "preview": preview(chunk["text"]),
        "terms": dict(terms),
        "length": sum(terms.values()),
    }


def worded_file(name, text):
    return [worded_chunk(chunk) for chunk in file_chunks(name, text)]


def preview(chunk_text):
    body = chunk_text.split("\n")[1:]
    meaningful = (line.strip() for line in body if line.strip() and not line.startswith("#!"))
    return next((line[:PREVIEW_CHARS] for line in meaningful), "")


def file_signature(path):
    info = path.stat()
    return [info.st_size, info.st_mtime_ns]


def refreshed_entry(name, root, known):
    signature = file_signature(root / name)
    if known and known.get("stat") == signature:
        return known
    text = read_text(root / name)
    if text is None:
        return None
    digest = hashlib.sha1(text.encode("utf-8")).hexdigest()
    if known and known["hash"] == digest:
        return {**known, "stat": signature}
    return {"hash": digest, "stat": signature, "chunks": worded_file(name, text)}


def refreshed_index(root, files):
    current = {}
    for name in candidate_files(root):
        entry = refreshed_entry(name, root, files.get(name))
        if entry is not None:
            current[name] = entry
    return current


def flat_chunks(files):
    return [(name, chunk) for name, entry in files.items() for chunk in entry["chunks"]]


def query_groups(query):
    return [variants(stem(word)) for word in dict.fromkeys(words(query)) if word not in STOP_WORDS]


def lexical_ranking(chunks, query):
    groups = query_groups(query)
    if not groups or not chunks:
        return []
    average_length = sum(chunk["length"] for _, chunk in chunks) / len(chunks)
    hits = [[sum(chunk["terms"].get(form, 0) for form in group) for group in groups] for _, chunk in chunks]
    containing = [sum(1 for chunk_hits in hits if chunk_hits[i]) for i in range(len(groups))]
    idf = [math.log(1 + (len(chunks) - count + 0.5) / (count + 0.5)) for count in containing]
    scored = []
    for position, ((_, chunk), chunk_hits) in enumerate(zip(chunks, hits)):
        length_norm = BM25_K1 * (1 - BM25_B + BM25_B * chunk["length"] / average_length)
        score = sum(idf[i] * tf * (BM25_K1 + 1) / (tf + length_norm) for i, tf in enumerate(chunk_hits) if tf)
        if score > 0:
            scored.append((score, position))
    return top_positions(scored)


def semantic_ranking(chunks, query_vector):
    scored = []
    for position, (_, chunk) in enumerate(chunks):
        if "vector" in chunk:
            score = sum(a * b for a, b in zip(query_vector, chunk["vector"]))
            if score > 0:
                scored.append((score, position))
    return top_positions(scored)


def top_positions(scored):
    return [position for _, position in heapq.nlargest(CANDIDATES, scored, key=lambda item: item[0])]


def fused_ranking(rankings, limit):
    scores = {}
    for ranking in rankings:
        for rank, position in enumerate(ranking):
            scores[position] = scores.get(position, 0.0) + 1 / (RRF_K + rank)
    return heapq.nlargest(limit, scores.items(), key=lambda item: item[1])


def embedding_loaded():
    try:
        with urllib.request.urlopen(f"{OLLAMA_URL}/api/ps", timeout=PS_TIMEOUT) as response:
            loaded = json.load(response).get("models", [])
    except (urllib.error.URLError, OSError, ValueError):
        return False
    return any(EMBED_MODEL in (model.get("name"), model.get("model")) for model in loaded)


def result_line(chunks, position, score, top_score):
    name, chunk = chunks[position]
    return f"{name}:{chunk['start']}-{chunk['end']}  {score / top_score:.2f}  {chunk['preview']}"


STATE = {"path": None, "loaded_mtime": None, "files": {}}


def index_mtime(path):
    try:
        return path.stat().st_mtime_ns
    except OSError:
        return None


def current_files(root):
    path = index_path(root)
    mtime = index_mtime(path)
    if STATE["path"] != path or (mtime is not None and mtime != STATE["loaded_mtime"]):
        STATE.update(path=path, loaded_mtime=mtime, files=load_index(path))
    STATE["files"] = refreshed_index(root, STATE["files"])
    return STATE["files"]


def embedded_chunks(name, text):
    chunks = file_chunks(name, text)
    vectors = embed([chunk["text"] for chunk in chunks])
    return [{**worded_chunk(chunk), "vector": vector} for chunk, vector in zip(chunks, vectors)]


def lacks_vectors(entry):
    return any("vector" not in chunk for chunk in entry["chunks"])


def embed_missing_vectors(root, files):
    for name, entry in files.items():
        if not lacks_vectors(entry):
            continue
        text = read_text(root / name)
        if text is not None:
            entry["chunks"] = embedded_chunks(name, text)


def build_index():
    root = repo_root()
    path = index_path(root)
    files = refreshed_index(root, load_index(path))
    save_index(path, files)
    if embedding_available():
        embed_missing_vectors(root, files)
        save_index(path, files)
    return len(files)


def embedding_available():
    return EMBED_ALLOWED or embedding_loaded()


def rankings(chunks, query):
    ranked = [lexical_ranking(chunks, query)]
    if not embedding_available():
        return ranked, WORDS_ONLY_NOTE
    try:
        query_vectors = embed([QUERY_INSTRUCTION + query])
    except SearchError as error:
        return ranked, f"words only: {error}"
    if query_vectors:
        ranked.append(semantic_ranking(chunks, query_vectors[0]))
    return ranked, None


def search(query, limit):
    chunks = flat_chunks(current_files(repo_root()))
    if not chunks:
        return "No indexed code yet."
    ranked, note = rankings(chunks, query)
    fused = fused_ranking(ranked, limit)
    lines = [result_line(chunks, position, score, fused[0][1]) for position, score in fused] or ["No matching code."]
    return "\n".join(lines + [note] if note else lines)


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


def error_response(message_id, code, text):
    return {"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": text}}


def response(message):
    method = message.get("method")
    handler = HANDLERS.get(method) if isinstance(method, str) else None
    if handler is None:
        return error_response(message.get("id"), -32601, "Method not found")
    params = message.get("params")
    if params is not None and not isinstance(params, dict):
        return error_response(message.get("id"), -32602, "params must be an object")
    try:
        return {"jsonrpc": "2.0", "id": message["id"], "result": handler(params or {})}
    except Exception as error:
        return error_response(message["id"], -32603, f"{type(error).__name__}: {error}")


def parsed_message(line):
    try:
        message = json.loads(line)
    except (ValueError, RecursionError):
        return None
    return message if isinstance(message, dict) else None


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
        message = parsed_message(line)
        if message is not None and "id" in message:
            try:
                reply = json.dumps(response(message))
            except RecursionError:
                continue
            print(reply, flush=True)


main()

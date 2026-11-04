#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from urllib.parse import parse_qs, urlsplit

DEFAULT_BUILD = 11429
DEFAULT_COMMIT = "d81235049"
DEFAULT_MODELS_MAX = 2
DEFAULT_EMBEDDING_DIMS = 8
DEFAULT_REPLY = {"text": "stub reply", "thinking": "stub thinking"}
THINK_SUFFIX = "@think"
CREATED = 1793751785
state_lock = Lock()


def parse_options():
    parser = argparse.ArgumentParser(prog="stub-llama-server.py", description="A llama-server in router mode, for tests")
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--log", required=True)
    return parser.parse_args()


class StubState:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.read()

    def read(self):
        try:
            data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            data = {}
        data.setdefault("models", {})
        data.setdefault("loaded", [])
        data.setdefault("loading", {})
        data.setdefault("counters", {})
        return data

    def save(self):
        handle, temporary = tempfile.mkstemp(dir=self.path.parent, prefix=".stub-state.")
        with os.fdopen(handle, "w") as stream:
            json.dump(self.data, stream, indent=1)
        os.replace(temporary, self.path)

    def count(self, key):
        self.data["counters"][key] = self.data["counters"].get(key, 0) + 1

    def resolve(self, name):
        models = self.data["models"]
        if name in models:
            return name
        return next((model_id for model_id, spec in models.items() if name in spec.get("aliases", [])), None)

    def build_info(self):
        return f"b{self.data.get('build', DEFAULT_BUILD)}-{self.data.get('commit', DEFAULT_COMMIT)}"

    def status_of(self, model_id):
        if model_id not in self.data["loaded"]:
            return "unloaded"
        return "loading" if self.data["loading"].get(model_id, 0) > 0 else "loaded"

    def tick_loading(self):
        for model_id, polls in list(self.data["loading"].items()):
            self.data["loading"][model_id] = max(polls - 1, 0)

    def load(self, model_id):
        loaded = self.data["loaded"]
        if model_id in loaded:
            loaded.remove(model_id)
            loaded.append(model_id)
            return
        models_max = self.data.get("models_max", DEFAULT_MODELS_MAX)
        while models_max and len(loaded) >= models_max:
            self.data["loading"].pop(loaded.pop(0), None)
        loaded.append(model_id)
        self.data["loading"][model_id] = self.data.get("load_polls", 0)

    def unload(self, model_id):
        self.data["loaded"].remove(model_id)
        self.data["loading"].pop(model_id, None)

    def entry(self, model_id):
        spec = self.data["models"][model_id]
        status = self.status_of(model_id)
        entry = {
            "id": model_id,
            "aliases": spec.get("aliases", []),
            "tags": [],
            "object": "model",
            "owned_by": "llamacpp",
            "created": CREATED,
            "status": {"value": status, "args": [], "preset": f"[{model_id}]\n"},
            "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]},
            "source": "preset",
            "can_remove": False,
        }
        if status == "loaded":
            entry["meta"] = {"n_ctx": spec.get("n_ctx", 0), "size": spec.get("size", 0)}
        return entry


def error_body(code, message, kind):
    return {"error": {"code": code, "message": message, "type": kind}}


def token_count(value):
    return max(1, len(json.dumps(value)) // 4)


def vector_for(text, dims):
    digest = hashlib.sha256(text.encode()).digest()
    return [round((digest[index % len(digest)] - 128) / 128, 6) for index in range(dims)]


def reply_blocks(state, model_id):
    reply = {**DEFAULT_REPLY, **state.data.get("reply", {})}
    blocks = [{"type": "text", "text": reply["text"]}]
    if model_id.endswith(THINK_SUFFIX):
        blocks.insert(0, {"type": "thinking", "thinking": reply["thinking"], "signature": ""})
    return blocks


def message_reply(state, body, model_id):
    blocks = reply_blocks(state, model_id)
    usage = {"cache_read_input_tokens": 0, "input_tokens": token_count(body.get("messages", [])), "output_tokens": len(blocks) * 4}
    usage.update(state.data.get("usage", {}))
    return {
        "id": "chatcmpl-stub",
        "type": "message",
        "role": "assistant",
        "content": blocks,
        "model": body.get("model"),
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": usage,
    }


def delta_of(block):
    if block["type"] == "thinking":
        return {"type": "thinking_delta", "thinking": block["thinking"]}
    return {"type": "text_delta", "text": block["text"]}


def empty_block(block):
    return {"type": "thinking", "thinking": ""} if block["type"] == "thinking" else {"type": "text", "text": ""}


def stream_events(reply):
    start = {**reply, "content": [], "stop_reason": None, "usage": {**reply["usage"], "output_tokens": 0}}
    yield "message_start", {"type": "message_start", "message": start}
    for index, block in enumerate(reply["content"]):
        yield "content_block_start", {"type": "content_block_start", "index": index, "content_block": empty_block(block)}
        yield "content_block_delta", {"type": "content_block_delta", "index": index, "delta": delta_of(block)}
        yield "content_block_stop", {"type": "content_block_stop", "index": index}
    delta = {"stop_reason": "end_turn", "stop_sequence": None}
    yield "message_delta", {"type": "message_delta", "delta": delta, "usage": {"output_tokens": reply["usage"]["output_tokens"]}}
    yield "message_stop", None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        return

    def do_GET(self):
        self.handle_request("GET")

    def do_POST(self):
        self.handle_request("POST")

    def read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw) if raw else {}
        except ValueError:
            return {}

    def handle_request(self, method):
        body = self.read_body()
        url = urlsplit(self.path)
        with open(self.server.log_path, "a") as log:
            log.write(json.dumps({"method": method, "path": self.path, "body": body}) + "\n")
        with state_lock:
            state = StubState(self.server.state_path)
            state.count(f"{method} {url.path}")
            code, payload = self.route(state, method, url, body)
            state.save()
        if isinstance(payload, list):
            self.send_events(payload)
        else:
            self.send_json(code, payload)

    def route(self, state, method, url, body):
        if url.path in state.data.get("fail_paths", []):
            return 500, error_body(500, "stub failure", "server_error")
        routes = {
            ("GET", "/health"): self.health,
            ("GET", "/props"): self.props,
            ("GET", "/models"): self.models,
            ("GET", "/v1/models"): self.models,
            ("POST", "/models/load"): self.load,
            ("POST", "/models/unload"): self.unload,
            ("POST", "/v1/embeddings"): self.embeddings,
            ("POST", "/v1/messages"): self.messages,
            ("POST", "/v1/messages/count_tokens"): self.count_tokens,
            ("POST", "/slots/0"): self.erase_slot,
        }
        route = routes.get((method, url.path))
        if route is None:
            return 404, error_body(404, "File Not Found", "not_found_error")
        return route(state, body, parse_qs(url.query))

    def health(self, state, _body, _query):
        code = state.data.get("health_status", 200)
        if code == 200:
            return 200, {"status": "ok"}
        return code, error_body(code, "Loading model", "unavailable_error")

    def props(self, state, _body, _query):
        return 200, {
            "role": "router",
            "max_instances": state.data.get("models_max", DEFAULT_MODELS_MAX),
            "models_autoload": True,
            "model_alias": "llama-server",
            "model_path": "none",
            "build_info": state.build_info(),
        }

    def models(self, state, _body, _query):
        listing = {"data": [state.entry(model_id) for model_id in state.data["models"]], "object": "list"}
        state.tick_loading()
        return 200, listing

    def load(self, state, body, _query):
        model_id = state.resolve(body.get("model", ""))
        if model_id is None:
            return 404, error_body(404, "File Not Found", "not_found_error")
        state.load(model_id)
        return 200, {"success": True}

    def unload(self, state, body, _query):
        model_id = state.resolve(body.get("model", ""))
        if model_id is None or model_id not in state.data["loaded"]:
            return 400, error_body(400, "model is not running", "invalid_request_error")
        state.unload(model_id)
        return 200, {"success": True}

    def requested_model(self, state, body):
        model_id = state.resolve(body.get("model", ""))
        if model_id is not None:
            state.load(model_id)
        return model_id

    def unknown_model(self, body):
        return 400, error_body(400, f"model '{body.get('model')}' not found", "invalid_request_error")

    def embeddings(self, state, body, _query):
        if self.requested_model(state, body) is None:
            return self.unknown_model(body)
        texts = body.get("input", [])
        texts = [texts] if isinstance(texts, str) else texts
        dims = state.data.get("embedding_dims", DEFAULT_EMBEDDING_DIMS)
        data = [{"embedding": vector_for(text, dims), "index": index, "object": "embedding"} for index, text in enumerate(texts)]
        tokens = sum(token_count(text) for text in texts)
        return 200, {"model": body.get("model"), "object": "list", "usage": {"prompt_tokens": tokens, "total_tokens": tokens}, "data": data}

    def messages(self, state, body, _query):
        model_id = self.requested_model(state, body)
        if model_id is None:
            return self.unknown_model(body)
        reply = message_reply(state, body, model_id)
        if body.get("stream"):
            return 200, list(stream_events(reply))
        return 200, reply

    def count_tokens(self, state, body, _query):
        if state.resolve(body.get("model", "")) is None:
            return self.unknown_model(body)
        return 200, {"input_tokens": token_count(body.get("messages", []))}

    def erase_slot(self, state, body, query):
        if "model" not in query and "model" not in body:
            return 400, error_body(400, "model name is missing from the request", "invalid_request_error")
        return 200, {"id_slot": 0, "n_erased": 0}

    def send_json(self, code, payload):
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_events(self, events):
        text = "".join(f"event: {name}\n" + (f"data: {json.dumps(data, separators=(',', ':'))}\n" if data is not None else "") + "\n" for name, data in events)
        data = text.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class QuietServer(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        return


def main():
    options = parse_options()
    server = QuietServer(("127.0.0.1", 0), Handler)
    server.state_path = options.state
    server.log_path = options.log
    port_file = Path(options.port_file)
    temporary = port_file.with_name(port_file.name + ".tmp")
    temporary.write_text(str(server.server_address[1]))
    os.replace(temporary, port_file)
    server.serve_forever()


if __name__ == "__main__":
    main()

import json
import os
import time
import urllib.error
import urllib.request

DEFAULT_URL = "http://127.0.0.1:11435"
DEFAULT_LOAD_TIMEOUT = 600
DEFAULT_LOAD_POLL = 1.0
REQUEST_TIMEOUT = 30


class ModelServerError(Exception):
    pass


def server_url():
    return os.environ.get("LLAMA_SERVER_URL") or DEFAULT_URL


def request(method, path, body=None, timeout=REQUEST_TIMEOUT):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data is not None else {}
    call = urllib.request.Request(server_url() + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(call, timeout=timeout) as response:
        return json.loads(response.read() or b"null")


def up():
    try:
        request("GET", "/health", timeout=5)
    except (OSError, ValueError):
        return False
    return True


def entries():
    try:
        return request("GET", "/models", timeout=5).get("data", [])
    except (OSError, ValueError, AttributeError):
        return []


def entry(model_id):
    return next((item for item in entries() if model_id == item.get("id") or model_id in item.get("aliases", [])), None)


def listed():
    return [name for item in entries() for name in [item.get("id"), *item.get("aliases", [])]]


def loaded(model_id):
    found = entry(model_id)
    return bool(found) and found.get("status", {}).get("value") == "loaded"


def failure(error):
    return f"HTTP {error.code}" if isinstance(error, urllib.error.HTTPError) else str(error)


def load(model_id):
    if loaded(model_id):
        return True
    try:
        request("POST", "/models/load", {"model": model_id})
    except (OSError, ValueError) as error:
        raise ModelServerError(f"could not load {model_id}: {failure(error)}") from error
    timeout = float(os.environ.get("MODEL_LOAD_TIMEOUT") or DEFAULT_LOAD_TIMEOUT)
    poll = float(os.environ.get("MODEL_LOAD_POLL") or DEFAULT_LOAD_POLL)
    deadline = time.monotonic() + timeout
    while not loaded(model_id):
        if time.monotonic() >= deadline:
            raise ModelServerError(f"{model_id} did not load within {timeout:g}s")
        time.sleep(poll)
    return True


def unload(model_id):
    if not loaded(model_id):
        return True
    try:
        request("POST", "/models/unload", {"model": model_id})
    except (OSError, ValueError) as error:
        raise ModelServerError(f"could not unload {model_id}: {failure(error)}") from error
    return True


def embed(model_id, texts):
    try:
        reply = request("POST", "/v1/embeddings", {"model": model_id, "input": list(texts)})
    except (OSError, ValueError) as error:
        raise ModelServerError(f"could not embed with {model_id}: {failure(error)}") from error
    return [item["embedding"] for item in sorted(reply.get("data", []), key=lambda item: item.get("index", 0))]

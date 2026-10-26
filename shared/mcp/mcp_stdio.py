import json
import sys


def tool_result(text, is_error=False):
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def initialize_result(server_name, params):
    return {
        "protocolVersion": params.get("protocolVersion", "2025-06-18"),
        "capabilities": {"tools": {}},
        "serverInfo": {"name": server_name, "version": "1.0.0"},
    }


def error_response(message_id, code, text):
    return {"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": text}}


def response(handlers, message):
    method = message.get("method")
    handler = handlers.get(method) if isinstance(method, str) else None
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


def serve(server_name, list_tools, call_tool):
    handlers = {
        "initialize": lambda params: initialize_result(server_name, params),
        "ping": lambda params: {},
        "tools/list": lambda params: {"tools": list_tools()},
        "tools/call": call_tool,
    }
    for line in sys.stdin:
        if not line.strip():
            continue
        message = parsed_message(line)
        if message is not None and "id" in message:
            try:
                reply = json.dumps(response(handlers, message))
            except RecursionError:
                continue
            print(reply, flush=True)

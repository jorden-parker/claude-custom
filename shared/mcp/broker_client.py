import json
import os
import socket

BROKER_TIMEOUT_SECONDS = 150
GH_BROKER_ADDRESS = "CLAUDE_OLLAMA_GH_BROKER"


class BrokerMissing(Exception):
    pass


def send_request(address_variable, request):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(BROKER_TIMEOUT_SECONDS)
        try:
            connection.connect(os.environ.get(address_variable, ""))
        except OSError:
            raise BrokerMissing from None
        connection.sendall(json.dumps(request).encode() + b"\n")
        with connection.makefile("rb") as replies:
            return json.loads(replies.readline())


def ask_broker(name, arguments):
    return send_request(GH_BROKER_ADDRESS, {"tool": name, "arguments": arguments})

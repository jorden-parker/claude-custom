import json
import os
import socket

BROKER_TIMEOUT_SECONDS = 150
BROKER_ADDRESS = "CLAUDE_OLLAMA_GH_BROKER"


class BrokerMissing(Exception):
    pass


def ask_broker(name, arguments):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(BROKER_TIMEOUT_SECONDS)
        try:
            connection.connect(os.environ.get(BROKER_ADDRESS, ""))
        except OSError:
            raise BrokerMissing from None
        connection.sendall(json.dumps({"tool": name, "arguments": arguments}).encode() + b"\n")
        with connection.makefile("rb") as replies:
            return json.loads(replies.readline())

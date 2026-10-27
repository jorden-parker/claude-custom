import sys

from broker_client import BrokerMissing, send_request

SHORTCUT_BROKER_ADDRESS = "CLAUDE_OLLAMA_SHORTCUT_BROKER"
BROKER_MISSING = (
    "short (claude-ollama): the Shortcut broker is not running; check short works outside the session, then relaunch"
)


def main():
    try:
        reply = send_request(SHORTCUT_BROKER_ADDRESS, {"argv": sys.argv[1:]})
    except BrokerMissing:
        sys.stderr.write(f"{BROKER_MISSING}\n")
        return 1
    sys.stdout.write(reply.get("stdout", ""))
    sys.stderr.write(reply.get("stderr", ""))
    return reply.get("exit", 1)


if __name__ == "__main__":
    sys.exit(main())

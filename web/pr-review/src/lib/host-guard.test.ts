import { describe, expect, it } from "vitest";
import { isLoopbackHost } from "./host-guard";

describe("isLoopbackHost", () => {
  it.each(["127.0.0.1:8765", "127.0.0.1", "localhost:8765", "localhost", "LOCALHOST:8765"])(
    "accepts the loopback host %s",
    (host) => {
      expect(isLoopbackHost(host)).toBe(true);
    },
  );

  it.each([
    "attacker.example:8765",
    "attacker.example",
    "127.0.0.1.attacker.example:8765",
    "localhost.attacker.example:8765",
    "127.0.0.1:8765.attacker.example",
    "attacker.example@127.0.0.1:8765",
    "127.0.0.2:8765",
    "",
  ])("rejects the foreign host %s", (host) => {
    expect(isLoopbackHost(host)).toBe(false);
  });

  it("rejects a request without a Host header", () => {
    expect(isLoopbackHost(null)).toBe(false);
  });
});

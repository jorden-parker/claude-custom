import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { proxy } from "./proxy";

const TOKEN = "3f9a0c1d2e4b5a6978869504a3b2c1d0e9f8a7b6c5d4e3f2";
const PAGE = "http://127.0.0.1:8765/reviews/20261021-174512-pr-7";

let tokenDir: string;

function requestFor(url: string, cookie?: string, host = "127.0.0.1:8765"): NextRequest {
  const headers: Record<string, string> = { host };
  if (cookie !== undefined) {
    headers.cookie = `console_token=${cookie}`;
  }
  return new NextRequest(url, { headers });
}

beforeEach(() => {
  tokenDir = fs.mkdtempSync(path.join(os.tmpdir(), "console-"));
  const tokenFile = path.join(tokenDir, "token");
  fs.writeFileSync(tokenFile, `${TOKEN}\n`);
  vi.stubEnv("CONSOLE_TOKEN_FILE", tokenFile);
});

afterEach(() => {
  vi.unstubAllEnvs();
  fs.rmSync(tokenDir, { recursive: true, force: true });
});

describe("proxy token gate", () => {
  it("refuses the bare link", () => {
    expect(proxy(requestFor(PAGE)).status).toBe(401);
  });

  it("refuses a wrong token in the link", () => {
    expect(proxy(requestFor(`${PAGE}?token=not-the-token`)).status).toBe(401);
  });

  it("accepts the tokened link and redirects to the page without the token", () => {
    const response = proxy(requestFor(`${PAGE}?token=${TOKEN}`));
    const location = new URL(response.headers.get("location") ?? "");
    expect(response.status).toBe(307);
    expect(location.pathname).toBe("/reviews/20261021-174512-pr-7");
    expect(location.searchParams.has("token")).toBe(false);
  });

  it("sets an HttpOnly SameSite=Strict cookie when the tokened link is accepted", () => {
    const cookie = proxy(requestFor(`${PAGE}?token=${TOKEN}`)).headers.get("set-cookie") ?? "";
    expect(cookie).toContain(`console_token=${TOKEN}`);
    expect(cookie).toMatch(/HttpOnly/i);
    expect(cookie).toMatch(/SameSite=strict/i);
  });

  it("passes a request that carries the token cookie", () => {
    const response = proxy(requestFor(PAGE, TOKEN));
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });

  it("refuses a request whose cookie holds the wrong token", () => {
    expect(proxy(requestFor(PAGE, "not-the-token")).status).toBe(401);
  });

  it("refuses every request when CONSOLE_TOKEN_FILE is unset", () => {
    delete process.env.CONSOLE_TOKEN_FILE;
    expect(proxy(requestFor(`${PAGE}?token=${TOKEN}`)).status).toBe(401);
    expect(proxy(requestFor(PAGE, TOKEN)).status).toBe(401);
  });

  it("refuses every request when the token file is missing", () => {
    vi.stubEnv("CONSOLE_TOKEN_FILE", path.join(tokenDir, "missing"));
    expect(proxy(requestFor(`${PAGE}?token=${TOKEN}`)).status).toBe(401);
    expect(proxy(requestFor(PAGE, TOKEN)).status).toBe(401);
  });
});

describe("proxy host gate", () => {
  it("answers 403 to a request whose Host is a rebound domain, even with the token", () => {
    expect(proxy(requestFor(`${PAGE}?token=${TOKEN}`, undefined, "attacker.example:8765")).status).toBe(403);
  });

  it("answers 403 to a request without a loopback Host", () => {
    expect(proxy(requestFor(PAGE, TOKEN, "192.168.1.20:8765")).status).toBe(403);
  });

  it("lets a tokened request addressed to localhost through", () => {
    expect(proxy(requestFor(PAGE, TOKEN, "localhost:8765")).headers.get("x-middleware-next")).toBe("1");
  });
});

import { timingSafeEqual } from "node:crypto";
import { readFileSync } from "node:fs";
import { NextResponse, type NextRequest } from "next/server";
import { isLoopbackHost } from "@/lib/host-guard";

const TOKEN_PARAM = "token";
const TOKEN_COOKIE = "console_token";
const READ_METHODS = ["GET", "HEAD"];

export function proxy(request: NextRequest) {
  if (!isLoopbackHost(request.headers.get("host"))) {
    return new NextResponse("Forbidden", { status: 403 });
  }
  if (!isSameOriginWrite(request)) {
    return new NextResponse("Forbidden", { status: 403 });
  }
  const expected = expectedToken();
  if (expected === "") {
    return unauthorized();
  }
  if (linkCarriesToken(request, expected)) {
    return grantCookieAndHop(request, expected);
  }
  if (cookieCarriesToken(request, expected)) {
    return NextResponse.next();
  }
  return unauthorized();
}

function isSameOriginWrite(request: NextRequest): boolean {
  if (READ_METHODS.includes(request.method)) {
    return true;
  }
  return request.headers.get("origin") === `http://${request.headers.get("host")}`;
}

function expectedToken(): string {
  const file = process.env.CONSOLE_TOKEN_FILE;
  if (!file) {
    return "";
  }
  try {
    return readFileSync(file, "utf8").trim();
  } catch {
    return "";
  }
}

function linkCarriesToken(request: NextRequest, expected: string): boolean {
  const queryToken = request.nextUrl.searchParams.get(TOKEN_PARAM);
  return queryToken !== null && tokensMatch(queryToken, expected);
}

function cookieCarriesToken(request: NextRequest, expected: string): boolean {
  const cookieToken = request.cookies.get(TOKEN_COOKIE)?.value;
  return cookieToken !== undefined && tokensMatch(cookieToken, expected);
}

function tokensMatch(candidate: string, expected: string): boolean {
  const given = Buffer.from(candidate);
  const wanted = Buffer.from(expected);
  return given.length === wanted.length && timingSafeEqual(given, wanted);
}

function escapeAttribute(text: string): string {
  return text.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function urlWithoutToken(request: NextRequest): string {
  const target = request.nextUrl.clone();
  target.searchParams.delete(TOKEN_PARAM);
  return `http://${request.headers.get("host")}${target.pathname}${target.search}`;
}

function grantCookieAndHop(request: NextRequest, token: string) {
  const target = escapeAttribute(urlWithoutToken(request));
  const response = new NextResponse(`<!doctype html><meta http-equiv="refresh" content="0;url=${target}">\n`, {
    headers: { "content-type": "text/html; charset=utf-8" },
  });
  response.cookies.set(TOKEN_COOKIE, token, {
    httpOnly: true,
    sameSite: "strict",
    path: "/",
  });
  return response;
}

function unauthorized() {
  return new NextResponse("Unauthorized", { status: 401 });
}

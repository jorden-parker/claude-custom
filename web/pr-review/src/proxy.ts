import { timingSafeEqual } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { isLoopbackHost } from "@/lib/host-guard";

const TOKEN_PARAM = "token";
const TOKEN_COOKIE = "pr_review_token";

export function proxy(request: NextRequest) {
  if (!isLoopbackHost(request.headers.get("host"))) {
    return new NextResponse("Forbidden", { status: 403 });
  }
  const expected = process.env.PR_REVIEW_TOKEN ?? "";
  if (expected === "") {
    return unauthorized();
  }
  if (linkCarriesToken(request, expected)) {
    return grantCookieAndRedirect(request, expected);
  }
  if (cookieCarriesToken(request, expected)) {
    return NextResponse.next();
  }
  return unauthorized();
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

function grantCookieAndRedirect(request: NextRequest, token: string) {
  const target = request.nextUrl.clone();
  target.searchParams.delete(TOKEN_PARAM);
  const response = NextResponse.redirect(target);
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

import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const response = NextResponse.redirect(new URL("/login", request.url), 303);
  response.cookies.delete("ops_access_token");
  response.cookies.delete("ops_access_expires_at");
  response.cookies.delete("ops_refresh_token");
  return response;
}

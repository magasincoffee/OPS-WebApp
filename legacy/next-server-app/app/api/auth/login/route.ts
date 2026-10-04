import { NextResponse } from "next/server";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

type AuthPayload = {
  access_token: string;
  refresh_token: string;
  expires_in?: number;
};

function loginRedirect(request: Request, error: string) {
  return NextResponse.redirect(
    new URL(`/login?error=${encodeURIComponent(error)}`, request.url),
    303,
  );
}

export async function POST(request: Request) {
  const formData = await request.formData();
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    return loginRedirect(request, "missing");
  }

  const { url, publishableKey } = getSupabasePublicConfig();
  const authResponse = await fetch(
    `${url}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: publishableKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, password }),
      cache: "no-store",
    },
  );

  if (!authResponse.ok) {
    return loginRedirect(request, "invalid");
  }

  const auth = (await authResponse.json()) as AuthPayload;
  const response = NextResponse.redirect(new URL("/customers", request.url), 303);
  const secure = process.env.NODE_ENV === "production";
  const maxAge = auth.expires_in ?? 3600;
  const now = Math.floor(Date.now() / 1000);

  response.cookies.set("ops_access_token", auth.access_token, {
    httpOnly: true,
    sameSite: "lax",
    secure,
    path: "/",
    maxAge,
  });
  response.cookies.set("ops_access_expires_at", String(now + maxAge), {
    httpOnly: true,
    sameSite: "lax",
    secure,
    path: "/",
    maxAge,
  });
  response.cookies.set("ops_refresh_token", auth.refresh_token, {
    httpOnly: true,
    sameSite: "lax",
    secure,
    path: "/",
    maxAge: 60 * 60 * 24 * 30,
  });

  return response;
}

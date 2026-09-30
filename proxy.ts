import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { getSupabasePublicConfig } from "@/lib/supabase/config";

type RefreshPayload = {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
};

export async function proxy(request: NextRequest) {
  const accessToken = request.cookies.get("ops_access_token")?.value;
  const refreshToken = request.cookies.get("ops_refresh_token")?.value;
  const expiresAt = Number(request.cookies.get("ops_access_expires_at")?.value ?? "0");
  const now = Math.floor(Date.now() / 1000);

  if (accessToken && expiresAt > now + 60) return NextResponse.next();

  if (!refreshToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  try {
    const { url, publishableKey } = getSupabasePublicConfig();
    const refreshResponse = await fetch(`${url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { apikey: publishableKey, "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
      cache: "no-store",
    });

    if (!refreshResponse.ok) throw new Error("Unable to refresh session");

    const refreshed = (await refreshResponse.json()) as RefreshPayload;
    const response = NextResponse.redirect(request.nextUrl, 303);
    const secure = process.env.NODE_ENV === "production";
    const maxAge = refreshed.expires_in ?? 3600;

    response.cookies.set("ops_access_token", refreshed.access_token, {
      httpOnly: true, sameSite: "lax", secure, path: "/", maxAge,
    });
    response.cookies.set("ops_access_expires_at", String(now + maxAge), {
      httpOnly: true, sameSite: "lax", secure, path: "/", maxAge,
    });

    if (refreshed.refresh_token) {
      response.cookies.set("ops_refresh_token", refreshed.refresh_token, {
        httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: 60 * 60 * 24 * 30,
      });
    }

    return response;
  } catch {
    const response = NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    response.cookies.delete("ops_access_token");
    response.cookies.delete("ops_access_expires_at");
    response.cookies.delete("ops_refresh_token");
    return response;
  }
}

export const config = {
  matcher: ["/customers/:path*", "/suppliers/:path*", "/products/:path*", "/costing/:path*", "/purchases/:path*", "/receipts/:path*", "/inventory/:path*"],
};

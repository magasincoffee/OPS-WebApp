import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "./config";

export class SupabaseRestError extends Error {
  constructor(
    public readonly status: number,
    public readonly responseBody: string,
  ) {
    super(`Supabase REST request failed with status ${status}`);
  }
}

export async function getAccessToken() {
  return (await cookies()).get("ops_access_token")?.value ?? null;
}

export async function supabaseRestWithToken<T>(
  path: string,
  accessToken: string,
  init: RequestInit = {},
): Promise<T> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const headers = new Headers(init.headers);

  headers.set("apikey", publishableKey);
  headers.set("Authorization", `Bearer ${accessToken}`);

  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers,
    cache: "no-store",
  });

  const responseText = await response.text();

  if (!response.ok) {
    throw new SupabaseRestError(response.status, responseText);
  }

  if (!responseText) {
    return null as T;
  }

  return JSON.parse(responseText) as T;
}

export async function supabaseRest<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const accessToken = await getAccessToken();

  if (!accessToken) {
    throw new SupabaseRestError(401, "AUTH_REQUIRED");
  }

  return supabaseRestWithToken<T>(path, accessToken, init);
}

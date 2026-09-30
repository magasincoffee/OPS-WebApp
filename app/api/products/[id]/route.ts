import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

function nullable(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim();
  return normalized || null;
}

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const name = String(formData.get("name") ?? "").trim();
  const variantId = String(formData.get("variant_id") ?? "").trim();

  if (!name || !variantId) {
    return NextResponse.redirect(new URL("/products?error=product_name", request.url), 303);
  }

  try {
    await supabaseRestWithToken(`products?id=eq.${encodeURIComponent(id)}`, accessToken, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        category_id: nullable(formData.get("category_id")),
        name,
        product_type: nullable(formData.get("product_type")),
        description: nullable(formData.get("description")),
        is_active: formData.get("is_active") === "on",
      }),
    });
    return NextResponse.redirect(
      new URL(`/products/${variantId}?product_saved=1`, request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(
      new URL(`/products/${variantId}?error=product_save`, request.url),
      303,
    );
  }
}

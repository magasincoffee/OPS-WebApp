import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

function nullable(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim();
  return normalized || null;
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const formData = await request.formData();
  const name = String(formData.get("name") ?? "").trim();
  if (!name) {
    return NextResponse.redirect(new URL("/products?error=product_name", request.url), 303);
  }

  try {
    await supabaseRestWithToken("products", accessToken, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        category_id: nullable(formData.get("category_id")),
        name,
        product_type: nullable(formData.get("product_type")),
        description: nullable(formData.get("description")),
        is_active: true,
      }),
    });
    return NextResponse.redirect(new URL("/products?product_saved=1", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/products?error=product_save", request.url), 303);
  }
}

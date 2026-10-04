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
  const variantId = String(formData.get("variant_id") ?? "").trim();
  const packageCode = String(formData.get("package_code") ?? "").trim();
  const packageName = String(formData.get("package_name") ?? "").trim();
  const units = Number(String(formData.get("units_per_package") ?? "").trim());
  const effectiveFrom = String(formData.get("effective_from") ?? "").trim();

  if (!variantId || !packageCode || !packageName || !Number.isFinite(units) || units <= 0 || !effectiveFrom) {
    return NextResponse.redirect(new URL("/products?error=packaging_required", request.url), 303);
  }

  try {
    await supabaseRestWithToken(`product_packaging?id=eq.${encodeURIComponent(id)}`, accessToken, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        package_code: packageCode,
        package_name: packageName,
        units_per_package: units,
        is_purchase_default: formData.get("is_purchase_default") === "on",
        is_sale_default: formData.get("is_sale_default") === "on",
        effective_from: effectiveFrom,
        effective_to: nullable(formData.get("effective_to")),
        is_active: formData.get("is_active") === "on",
      }),
    });
    return NextResponse.redirect(new URL(`/products/${variantId}?packaging_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/products/${variantId}?error=packaging_save`, request.url), 303);
  }
}

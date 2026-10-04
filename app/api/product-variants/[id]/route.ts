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

function positiveOrNull(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim();
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function nonnegative(value: FormDataEntryValue | null) {
  const parsed = Number(String(value ?? "0").trim() || "0");
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const skuCode = String(formData.get("sku_code") ?? "").trim();
  const baseUnit = String(formData.get("base_inventory_unit") ?? "").trim();

  if (!skuCode || !baseUnit) {
    return NextResponse.redirect(new URL(`/products/${id}?error=sku_required`, request.url), 303);
  }

  try {
    await supabaseRestWithToken(`product_variants?id=eq.${encodeURIComponent(id)}`, accessToken, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        sku_code: skuCode,
        variant_name: nullable(formData.get("variant_name")),
        capacity_value: positiveOrNull(formData.get("capacity_value")),
        capacity_unit: nullable(formData.get("capacity_unit")),
        base_inventory_unit: baseUnit,
        default_purchase_unit: nullable(formData.get("default_purchase_unit")),
        minimum_stock_quantity: nonnegative(formData.get("minimum_stock_quantity")),
        is_active: formData.get("is_active") === "on",
      }),
    });
    return NextResponse.redirect(new URL(`/products/${id}?sku_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/products/${id}?error=sku_save`, request.url), 303);
  }
}

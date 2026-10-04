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

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const formData = await request.formData();
  const productId = String(formData.get("product_id") ?? "").trim();
  const skuCode = String(formData.get("sku_code") ?? "").trim();
  const baseUnit = String(formData.get("base_inventory_unit") ?? "").trim();

  if (!productId || !skuCode || !baseUnit) {
    return NextResponse.redirect(new URL("/products?error=sku_required", request.url), 303);
  }

  try {
    const rows = await supabaseRestWithToken<Array<{ id: string }>>(
      "product_variants",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          product_id: productId,
          sku_code: skuCode,
          variant_name: nullable(formData.get("variant_name")),
          capacity_value: positiveOrNull(formData.get("capacity_value")),
          capacity_unit: nullable(formData.get("capacity_unit")),
          base_inventory_unit: baseUnit,
          default_purchase_unit: nullable(formData.get("default_purchase_unit")),
          minimum_stock_quantity: nonnegative(formData.get("minimum_stock_quantity")),
          is_active: true,
        }),
      },
    );
    const variantId = rows[0]?.id;
    return NextResponse.redirect(
      new URL(variantId ? `/products/${variantId}` : "/products?sku_saved=1", request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/products?error=sku_save", request.url), 303);
  }
}

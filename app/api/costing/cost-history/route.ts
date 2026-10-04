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

function nonnegative(value: FormDataEntryValue | null, fallback = 0) {
  const normalized = String(value ?? "").trim();
  if (!normalized) return fallback;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const formData = await request.formData();
  const productVariantId = String(formData.get("product_variant_id") ?? "").trim();
  const purchaseUnit = String(formData.get("purchase_unit") ?? "").trim();
  const units = Number(String(formData.get("units_per_purchase_unit") ?? "").trim());
  const purchasePrice = Number(String(formData.get("purchase_price_per_purchase_unit") ?? "").trim());
  const currency = String(formData.get("currency_code") ?? "VND").trim().toUpperCase();

  if (
    !productVariantId ||
    !purchaseUnit ||
    !Number.isFinite(units) ||
    units <= 0 ||
    !Number.isFinite(purchasePrice) ||
    purchasePrice < 0 ||
    !/^[A-Z]{3}$/.test(currency)
  ) {
    return NextResponse.redirect(new URL("/costing?error=cost_required", request.url), 303);
  }

  const inventoryBasisRaw = String(formData.get("inventory_cost_basis_per_base_unit") ?? "").trim();
  const inventoryBasis = inventoryBasisRaw ? Number(inventoryBasisRaw) : null;
  if (inventoryBasis !== null && (!Number.isFinite(inventoryBasis) || inventoryBasis < 0)) {
    return NextResponse.redirect(new URL("/costing?error=cost_required", request.url), 303);
  }

  try {
    await supabaseRestWithToken("purchase_cost_history", accessToken, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        product_variant_id: productVariantId,
        supplier_id: nullable(formData.get("supplier_id")),
        packaging_id: nullable(formData.get("packaging_id")),
        effective_at: String(formData.get("effective_at") ?? "").trim() || new Date().toISOString(),
        purchase_unit: purchaseUnit,
        units_per_purchase_unit: units,
        purchase_price_per_purchase_unit: purchasePrice,
        freight_cost_per_purchase_unit: nonnegative(formData.get("freight_cost_per_purchase_unit")),
        other_allocated_cost_per_purchase_unit: nonnegative(formData.get("other_allocated_cost_per_purchase_unit")),
        inventory_cost_basis_per_base_unit: inventoryBasis,
        currency_code: currency,
        source_reference: nullable(formData.get("source_reference")),
        notes: nullable(formData.get("notes")),
      }),
    });
    return NextResponse.redirect(new URL("/costing?cost_saved=1", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/costing?error=cost_save", request.url), 303);
  }
}

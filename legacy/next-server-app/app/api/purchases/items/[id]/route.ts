import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

type Packaging = {
  id: string;
  product_variant_id: string;
  package_name: string;
  units_per_package: number;
};

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const purchaseOrderId = String(formData.get("purchase_order_id") ?? "").trim();
  const productVariantId = String(formData.get("product_variant_id") ?? "").trim();
  const packagingId = String(formData.get("packaging_id") ?? "").trim();
  const packageQuantity = Number(String(formData.get("package_quantity") ?? "").trim());
  const unitCost = Number(String(formData.get("unit_cost_per_purchase_unit") ?? "").trim());
  let purchaseUnit = String(formData.get("purchase_unit") ?? "").trim();
  let unitsPerPurchaseUnit = Number(String(formData.get("units_per_purchase_unit") ?? "").trim());

  if (
    !purchaseOrderId ||
    !productVariantId ||
    !Number.isFinite(packageQuantity) ||
    packageQuantity <= 0 ||
    !Number.isFinite(unitCost) ||
    unitCost < 0
  ) {
    return NextResponse.redirect(new URL("/purchases?error=item_required", request.url), 303);
  }

  try {
    if (packagingId) {
      const rows = await supabaseRestWithToken<Packaging[]>(
        `product_packaging?id=eq.${encodeURIComponent(packagingId)}&select=id,product_variant_id,package_name,units_per_package`,
        accessToken,
      );
      const packaging = rows[0];
      if (!packaging || packaging.product_variant_id !== productVariantId) {
        return NextResponse.redirect(new URL(`/purchases/${purchaseOrderId}?error=packaging_mismatch`, request.url), 303);
      }
      unitsPerPurchaseUnit = Number(packaging.units_per_package);
      if (!purchaseUnit) purchaseUnit = packaging.package_name;
    }

    if (!purchaseUnit || !Number.isFinite(unitsPerPurchaseUnit) || unitsPerPurchaseUnit <= 0) {
      return NextResponse.redirect(new URL(`/purchases/${purchaseOrderId}?error=item_required`, request.url), 303);
    }

    await supabaseRestWithToken(
      `purchase_order_items?id=eq.${encodeURIComponent(id)}&purchase_order_id=eq.${encodeURIComponent(purchaseOrderId)}`,
      accessToken,
      {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          product_variant_id: productVariantId,
          packaging_id: packagingId || null,
          purchase_unit: purchaseUnit,
          package_quantity: packageQuantity,
          units_per_purchase_unit: unitsPerPurchaseUnit,
          unit_cost_per_purchase_unit: unitCost,
          notes: String(formData.get("notes") ?? "").trim() || null,
        }),
      },
    );

    return NextResponse.redirect(new URL(`/purchases/${purchaseOrderId}?item_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/purchases/${purchaseOrderId}?error=item_save`, request.url), 303);
  }
}

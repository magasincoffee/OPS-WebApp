import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

function redirectInventory(request: Request, query: string) {
  return NextResponse.redirect(new URL(`/inventory?${query}`, request.url), 303);
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) return NextResponse.redirect(new URL("/login?error=session", request.url), 303);

  const formData = await request.formData();
  const operation = String(formData.get("operation") ?? "").trim();

  try {
    if (operation === "create_stocktake") {
      const stocktakeNumber = String(formData.get("stocktake_number") ?? "").trim();
      const notes = String(formData.get("notes") ?? "").trim();
      if (!stocktakeNumber) return redirectInventory(request, "error=stocktake_number");

      const id = await supabaseRestWithToken<string>("rpc/create_stocktake", accessToken, {
        method: "POST",
        body: JSON.stringify({ p_stocktake_number: stocktakeNumber, p_notes: notes || null }),
      });
      return redirectInventory(request, `stocktake=${encodeURIComponent(id)}&action=created`);
    }

    if (operation === "count_stocktake") {
      const itemId = String(formData.get("stocktake_item_id") ?? "").trim();
      const stocktakeId = String(formData.get("stocktake_id") ?? "").trim();
      const counted = Number(String(formData.get("counted_quantity") ?? ""));
      const notes = String(formData.get("notes") ?? "").trim();
      if (!itemId || !stocktakeId || !Number.isFinite(counted) || counted < 0) {
        return redirectInventory(request, `stocktake=${encodeURIComponent(stocktakeId)}&error=count`);
      }
      await supabaseRestWithToken("rpc/set_stocktake_count", accessToken, {
        method: "POST",
        body: JSON.stringify({
          p_stocktake_item_id: itemId,
          p_counted_on_hand_quantity: counted,
          p_notes: notes || null,
        }),
      });
      return redirectInventory(request, `stocktake=${encodeURIComponent(stocktakeId)}&action=counted`);
    }

    if (operation === "finalize_stocktake" || operation === "post_stocktake") {
      const stocktakeId = String(formData.get("stocktake_id") ?? "").trim();
      if (!stocktakeId) return redirectInventory(request, "error=stocktake");
      const rpc = operation === "finalize_stocktake" ? "finalize_stocktake" : "post_stocktake";
      await supabaseRestWithToken(`rpc/${rpc}`, accessToken, {
        method: "POST",
        body: JSON.stringify({ p_stocktake_id: stocktakeId }),
      });
      return redirectInventory(
        request,
        `stocktake=${encodeURIComponent(stocktakeId)}&action=${operation === "finalize_stocktake" ? "finalized" : "posted"}`,
      );
    }

    if (operation === "adjust_inventory") {
      const variantId = String(formData.get("product_variant_id") ?? "").trim();
      const quantityDelta = Number(String(formData.get("quantity_delta") ?? ""));
      const reason = String(formData.get("reason") ?? "").trim();
      if (!variantId || !Number.isFinite(quantityDelta) || quantityDelta === 0 || !reason) {
        return redirectInventory(request, "error=adjustment");
      }
      await supabaseRestWithToken("rpc/adjust_inventory", accessToken, {
        method: "POST",
        body: JSON.stringify({
          p_product_variant_id: variantId,
          p_quantity_delta: quantityDelta,
          p_reason: reason,
        }),
      });
      return redirectInventory(request, "action=adjusted");
    }

    return redirectInventory(request, "error=operation");
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    const stocktakeId = String(formData.get("stocktake_id") ?? "").trim();
    const prefix = stocktakeId ? `stocktake=${encodeURIComponent(stocktakeId)}&` : "";
    return redirectInventory(request, `${prefix}error=${encodeURIComponent(operation || "operation")}`);
  }
}

import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

type SourceLine = {
  purchase_order_item_id: string;
  units_per_purchase_unit: number;
};

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const goodsReceiptId = String(formData.get("goods_receipt_id") ?? "").trim();
  const purchaseOrderItemId = String(formData.get("purchase_order_item_id") ?? "").trim();
  const packageQuantity = Number(String(formData.get("package_quantity") ?? "").trim());

  if (!goodsReceiptId || !purchaseOrderItemId || !Number.isFinite(packageQuantity) || packageQuantity <= 0) {
    return NextResponse.redirect(new URL("/receipts?error=item_required", request.url), 303);
  }

  try {
    const source = await supabaseRestWithToken<SourceLine[]>(
      `goods_receipt_source_lines?purchase_order_item_id=eq.${encodeURIComponent(purchaseOrderItemId)}&select=purchase_order_item_id,units_per_purchase_unit&limit=1`,
      accessToken,
    );
    const line = source[0];
    if (!line) {
      return NextResponse.redirect(new URL(`/receipts/${goodsReceiptId}?error=line_source`, request.url), 303);
    }

    await supabaseRestWithToken(
      `goods_receipt_items?id=eq.${encodeURIComponent(id)}&goods_receipt_id=eq.${encodeURIComponent(goodsReceiptId)}`,
      accessToken,
      {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          purchase_order_item_id: purchaseOrderItemId,
          package_quantity: packageQuantity,
          units_per_purchase_unit: Number(line.units_per_purchase_unit),
          notes: String(formData.get("notes") ?? "").trim() || null,
        }),
      },
    );

    return NextResponse.redirect(new URL(`/receipts/${goodsReceiptId}?item_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/receipts/${goodsReceiptId}?error=item_save`, request.url), 303);
  }
}

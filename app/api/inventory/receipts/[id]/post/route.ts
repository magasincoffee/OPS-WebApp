import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

type ReceiptItem = {
  id: string;
  goods_receipt_id: string;
  purchase_order_item_id: string;
  base_quantity: number;
};

type SourceLine = {
  purchase_order_item_id: string;
  product_variant_id: string;
};

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const requestedReceiptId = String(formData.get("goods_receipt_id") ?? "").trim();

  try {
    const rows = await supabaseRestWithToken<ReceiptItem[]>(
      `goods_receipt_items?id=eq.${encodeURIComponent(id)}&select=id,goods_receipt_id,purchase_order_item_id,base_quantity`,
      accessToken,
    );
    const item = rows[0];
    if (!item) {
      return NextResponse.redirect(new URL("/receipts?error=inventory_source", request.url), 303);
    }

    if (requestedReceiptId && requestedReceiptId !== item.goods_receipt_id) {
      return NextResponse.redirect(new URL(`/receipts/${item.goods_receipt_id}?error=inventory_source`, request.url), 303);
    }

    const source = await supabaseRestWithToken<SourceLine[]>(
      `goods_receipt_source_lines?purchase_order_item_id=eq.${encodeURIComponent(item.purchase_order_item_id)}&select=purchase_order_item_id,product_variant_id&limit=1`,
      accessToken,
    );
    const line = source[0];
    if (!line) {
      return NextResponse.redirect(new URL(`/receipts/${item.goods_receipt_id}?error=inventory_source`, request.url), 303);
    }

    await supabaseRestWithToken("inventory_movements", accessToken, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        product_variant_id: line.product_variant_id,
        movement_type: "GOODS_RECEIPT",
        quantity_delta_base_units: Number(item.base_quantity),
        inventory_reservation_id: null,
        goods_receipt_item_id: item.id,
        sales_order_item_id: null,
        reference: null,
        reason: null,
        created_by_user_id: null,
      }),
    });

    return NextResponse.redirect(
      new URL(`/receipts/${item.goods_receipt_id}?inventory_posted=1`, request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }

    const receiptId = requestedReceiptId || "";
    const target = receiptId ? `/receipts/${receiptId}` : "/receipts";
    const code = error instanceof SupabaseRestError && error.status === 409
      ? "already_posted"
      : "inventory_post";
    return NextResponse.redirect(new URL(`${target}?error=${code}`, request.url), 303);
  }
}

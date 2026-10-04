import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

type Receipt = { purchase_order_id: string };
type SourceLine = {
  purchase_order_id: string;
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
  const purchaseOrderItemId = String(formData.get("purchase_order_item_id") ?? "").trim();
  const packageQuantity = Number(String(formData.get("package_quantity") ?? "").trim());

  if (!purchaseOrderItemId || !Number.isFinite(packageQuantity) || packageQuantity <= 0) {
    return NextResponse.redirect(new URL(`/receipts/${id}?error=item_required`, request.url), 303);
  }

  try {
    const receipts = await supabaseRestWithToken<Receipt[]>(
      `goods_receipts?id=eq.${encodeURIComponent(id)}&select=purchase_order_id`,
      accessToken,
    );
    const receipt = receipts[0];
    if (!receipt) {
      return NextResponse.redirect(new URL("/receipts?error=source", request.url), 303);
    }

    const source = await supabaseRestWithToken<SourceLine[]>(
      `goods_receipt_source_lines?purchase_order_id=eq.${encodeURIComponent(receipt.purchase_order_id)}&purchase_order_item_id=eq.${encodeURIComponent(purchaseOrderItemId)}&select=purchase_order_id,purchase_order_item_id,units_per_purchase_unit&limit=1`,
      accessToken,
    );
    const line = source[0];
    if (!line) {
      return NextResponse.redirect(new URL(`/receipts/${id}?error=line_source`, request.url), 303);
    }

    await supabaseRestWithToken("goods_receipt_items", accessToken, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        goods_receipt_id: id,
        purchase_order_item_id: line.purchase_order_item_id,
        package_quantity: packageQuantity,
        units_per_purchase_unit: Number(line.units_per_purchase_unit),
        notes: String(formData.get("notes") ?? "").trim() || null,
      }),
    });

    return NextResponse.redirect(new URL(`/receipts/${id}?item_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/receipts/${id}?error=item_save`, request.url), 303);
  }
}

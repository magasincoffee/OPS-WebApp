import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type ReceiptSource = {
  purchase_order_id: string;
  payment_ready: boolean;
  po_status: string;
};

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
  const goodsReceiptNumber = String(formData.get("goods_receipt_number") ?? "").trim();
  const purchaseOrderId = String(formData.get("purchase_order_id") ?? "").trim();

  if (!goodsReceiptNumber || !purchaseOrderId) {
    return NextResponse.redirect(new URL("/receipts?error=required", request.url), 303);
  }

  try {
    const source = await supabaseRestWithToken<ReceiptSource[]>(
      `goods_receipt_source_lines?purchase_order_id=eq.${encodeURIComponent(purchaseOrderId)}&select=purchase_order_id,payment_ready,po_status&limit=1`,
      accessToken,
    );
    const po = source[0];

    if (!po) {
      return NextResponse.redirect(new URL("/receipts?error=source", request.url), 303);
    }
    if (!po.payment_ready) {
      return NextResponse.redirect(new URL("/receipts?error=payment", request.url), 303);
    }
    if (po.po_status === "CANCELLED") {
      return NextResponse.redirect(new URL("/receipts?error=cancelled", request.url), 303);
    }

    const rows = await supabaseRestWithToken<Array<{ id: string }>>(
      "goods_receipts",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          goods_receipt_number: goodsReceiptNumber,
          purchase_order_id: purchaseOrderId,
          document_reference: nullable(formData.get("document_reference")),
          notes: nullable(formData.get("notes")),
        }),
      },
    );

    const id = rows[0]?.id;
    return NextResponse.redirect(
      new URL(id ? `/receipts/${id}?created=1` : "/receipts?created=1", request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/receipts?error=save", request.url), 303);
  }
}

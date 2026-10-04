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

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const formData = await request.formData();
  const poNumber = String(formData.get("po_number") ?? "").trim();
  const supplierId = String(formData.get("supplier_id") ?? "").trim();
  const currencyCode = String(formData.get("currency_code") ?? "VND").trim().toUpperCase();
  const orderDate = String(formData.get("order_date") ?? "").trim();
  const freightAmount = Number(String(formData.get("freight_amount") ?? "0").trim() || "0");

  if (
    !poNumber ||
    !supplierId ||
    !orderDate ||
    !/^[A-Z]{3}$/.test(currencyCode) ||
    !Number.isFinite(freightAmount) ||
    freightAmount < 0
  ) {
    return NextResponse.redirect(new URL("/purchases?error=required", request.url), 303);
  }

  try {
    const rows = await supabaseRestWithToken<Array<{ id: string }>>(
      "purchase_orders",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          po_number: poNumber,
          supplier_id: supplierId,
          status: "DRAFT",
          order_date: orderDate,
          expected_receipt_date: nullable(formData.get("expected_receipt_date")),
          freight_amount: freightAmount,
          currency_code: currencyCode,
          payment_note: nullable(formData.get("payment_note")),
          document_reference: nullable(formData.get("document_reference")),
          responsible_user_id: nullable(formData.get("responsible_user_id")),
          notes: nullable(formData.get("notes")),
        }),
      },
    );

    const id = rows[0]?.id;
    return NextResponse.redirect(
      new URL(id ? `/purchases/${id}?created=1` : "/purchases?created=1", request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/purchases?error=save", request.url), 303);
  }
}

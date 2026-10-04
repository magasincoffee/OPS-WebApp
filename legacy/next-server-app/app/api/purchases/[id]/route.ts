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

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const status = String(formData.get("status") ?? "").trim();
  const orderDate = String(formData.get("order_date") ?? "").trim();
  const currencyCode = String(formData.get("currency_code") ?? "VND").trim().toUpperCase();
  const freightAmount = Number(String(formData.get("freight_amount") ?? "0").trim() || "0");

  if (
    !["DRAFT", "ORDERED", "CANCELLED"].includes(status) ||
    !orderDate ||
    !/^[A-Z]{3}$/.test(currencyCode) ||
    !Number.isFinite(freightAmount) ||
    freightAmount < 0
  ) {
    return NextResponse.redirect(new URL(`/purchases/${id}?error=required`, request.url), 303);
  }

  try {
    await supabaseRestWithToken(
      `purchase_orders?id=eq.${encodeURIComponent(id)}`,
      accessToken,
      {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          status,
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
    return NextResponse.redirect(new URL(`/purchases/${id}?saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/purchases/${id}?error=save`, request.url), 303);
  }
}

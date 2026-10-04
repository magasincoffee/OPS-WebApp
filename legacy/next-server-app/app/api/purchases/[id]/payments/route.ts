import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

type PurchaseOrder = { freight_amount: number; status: string };
type PurchaseOrderItem = { line_subtotal: number };
type PurchasePayment = { amount: number };

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
  const amount = Number(String(formData.get("amount") ?? "").trim());
  const paymentDate = String(formData.get("payment_date") ?? "").trim();

  if (!Number.isFinite(amount) || amount <= 0 || !paymentDate) {
    return NextResponse.redirect(new URL(`/purchases/${id}?error=payment_required`, request.url), 303);
  }

  try {
    const [orders, items, payments] = await Promise.all([
      supabaseRestWithToken<PurchaseOrder[]>(
        `purchase_orders?id=eq.${encodeURIComponent(id)}&select=freight_amount,status`,
        accessToken,
      ),
      supabaseRestWithToken<PurchaseOrderItem[]>(
        `purchase_order_items?purchase_order_id=eq.${encodeURIComponent(id)}&select=line_subtotal`,
        accessToken,
      ),
      supabaseRestWithToken<PurchasePayment[]>(
        `purchase_payments?purchase_order_id=eq.${encodeURIComponent(id)}&select=amount`,
        accessToken,
      ),
    ]);

    const order = orders[0];
    if (!order || order.status === "CANCELLED") {
      return NextResponse.redirect(new URL(`/purchases/${id}?error=cancelled`, request.url), 303);
    }

    const total =
      items.reduce((sum, item) => sum + Number(item.line_subtotal), 0) +
      Number(order.freight_amount);
    const alreadyPaid = payments.reduce((sum, payment) => sum + Number(payment.amount), 0);
    const outstanding = Math.max(0, total - alreadyPaid);

    if (total <= 0 || amount > outstanding + 0.000001) {
      return NextResponse.redirect(new URL(`/purchases/${id}?error=payment_exceeds_total`, request.url), 303);
    }

    const rows = await supabaseRestWithToken<Array<{ id: string }>>(
      "purchase_payments",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          purchase_order_id: id,
          amount,
          payment_date: paymentDate,
          payment_method: nullable(formData.get("payment_method")),
          reference: nullable(formData.get("reference")),
          evidence_attachment_id: null,
          created_by_user_id: null,
          notes: nullable(formData.get("notes")),
        }),
      },
    );

    const paymentId = rows[0]?.id;
    return NextResponse.redirect(
      new URL(
        paymentId
          ? `/purchases/${id}?payment_saved=1&payment_id=${paymentId}`
          : `/purchases/${id}?payment_saved=1`,
        request.url,
      ),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/purchases/${id}?error=payment_save`, request.url), 303);
  }
}

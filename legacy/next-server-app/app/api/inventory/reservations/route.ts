import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

function parseQuantity(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const quantity = Number(text);
  return Number.isFinite(quantity) && quantity > 0 ? quantity : Number.NaN;
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const formData = await request.formData();
  const salesOrderItemId = String(formData.get("sales_order_item_id") ?? "").trim();
  const quantity = parseQuantity(formData.get("quantity"));

  if (!salesOrderItemId || Number.isNaN(quantity)) {
    return NextResponse.redirect(new URL("/inventory?error=quantity", request.url), 303);
  }

  try {
    await supabaseRestWithToken("rpc/reserve_sales_order_item", accessToken, {
      method: "POST",
      body: JSON.stringify({
        p_sales_order_item_id: salesOrderItemId,
        p_quantity: quantity,
      }),
    });

    return NextResponse.redirect(new URL("/inventory?reservation=reserved", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/inventory?error=reserve", request.url), 303);
  }
}

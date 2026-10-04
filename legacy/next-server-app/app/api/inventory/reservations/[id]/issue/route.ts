import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

function parseQuantity(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const quantity = Number(text);
  return Number.isFinite(quantity) && quantity > 0 ? quantity : Number.NaN;
}

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const quantity = parseQuantity(formData.get("quantity"));

  if (!id || Number.isNaN(quantity)) {
    return NextResponse.redirect(new URL("/inventory?error=quantity", request.url), 303);
  }

  try {
    await supabaseRestWithToken("rpc/issue_inventory_reservation", accessToken, {
      method: "POST",
      body: JSON.stringify({
        p_inventory_reservation_id: id,
        p_quantity: quantity,
      }),
    });

    return NextResponse.redirect(new URL("/inventory?reservation=issued", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/inventory?error=issue", request.url), 303);
  }
}

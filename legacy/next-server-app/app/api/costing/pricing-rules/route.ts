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

function nullableInteger(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim();
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const formData = await request.formData();
  const name = String(formData.get("name") ?? "").trim();
  const printMode = String(formData.get("print_mode") ?? "ANY").trim();
  const currency = String(formData.get("currency_code") ?? "VND").trim().toUpperCase();
  const priority = Number(String(formData.get("priority") ?? "100").trim());

  if (
    !name ||
    !["ANY", "PRINTED", "PLAIN"].includes(printMode) ||
    !/^[A-Z]{3}$/.test(currency) ||
    !Number.isInteger(priority)
  ) {
    return NextResponse.redirect(new URL("/costing?error=rule_required", request.url), 303);
  }

  try {
    await supabaseRestWithToken("pricing_rules", accessToken, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        name,
        product_variant_id: nullable(formData.get("product_variant_id")),
        product_type: nullable(formData.get("product_type")),
        print_mode: printMode,
        min_print_colors: nullableInteger(formData.get("min_print_colors")),
        max_print_colors: nullableInteger(formData.get("max_print_colors")),
        currency_code: currency,
        priority,
        effective_from: String(formData.get("effective_from") ?? "").trim() || new Date().toISOString().slice(0, 10),
        effective_to: nullable(formData.get("effective_to")),
        is_active: true,
      }),
    });
    return NextResponse.redirect(new URL("/costing?rule_saved=1", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/costing?error=rule_save", request.url), 303);
  }
}

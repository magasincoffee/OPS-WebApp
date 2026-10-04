import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

function nullableNumber(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim();
  if (!normalized) return null;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const minQuantity = Number(String(formData.get("min_quantity_base_units") ?? "").trim());
  const maxQuantity = nullableNumber(formData.get("max_quantity_base_units"));
  const basis = String(formData.get("pricing_basis") ?? "").trim();
  const basisValue = Number(String(formData.get("pricing_basis_value") ?? "").trim());
  const printCost = Number(String(formData.get("print_cost_per_base_unit") ?? "0").trim() || "0");

  if (
    !Number.isFinite(minQuantity) || minQuantity <= 0 ||
    (maxQuantity !== null && maxQuantity < minQuantity) ||
    !["FIXED", "MARKUP", "MARGIN"].includes(basis) ||
    !Number.isFinite(basisValue) || basisValue < 0 ||
    (basis === "MARGIN" && basisValue >= 100) ||
    !Number.isFinite(printCost) || printCost < 0
  ) {
    return NextResponse.redirect(new URL("/costing?error=tier_required", request.url), 303);
  }

  try {
    await supabaseRestWithToken(`price_tiers?id=eq.${encodeURIComponent(id)}`, accessToken, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        min_quantity_base_units: minQuantity,
        max_quantity_base_units: maxQuantity,
        fixed_selling_price_per_base_unit: basis === "FIXED" ? basisValue : null,
        markup_percent: basis === "MARKUP" ? basisValue : null,
        margin_percent: basis === "MARGIN" ? basisValue : null,
        print_cost_per_base_unit: printCost,
      }),
    });
    return NextResponse.redirect(new URL("/costing?tier_saved=1", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL("/costing?error=tier_save", request.url), 303);
  }
}

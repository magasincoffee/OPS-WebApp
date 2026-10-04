import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = {
  params: Promise<{ id: string }>;
};

function nullable(value: FormDataEntryValue | null) {
  const normalized = String(value ?? "").trim();
  return normalized || null;
}

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();

  if (!accessToken) {
    return NextResponse.redirect(
      new URL("/login?error=session", request.url),
      303,
    );
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const productVariantId = String(
    formData.get("product_variant_id") ?? "",
  ).trim();

  if (!productVariantId) {
    return NextResponse.redirect(
      new URL(`/suppliers/${id}?error=product_variant`, request.url),
      303,
    );
  }

  const payload = {
    supplier_id: id,
    product_variant_id: productVariantId,
    packaging_id: null,
    supplier_sku: nullable(formData.get("supplier_sku")),
    purchase_unit: nullable(formData.get("purchase_unit")),
    is_preferred: formData.get("is_preferred") === "on",
    is_active: true,
  };

  try {
    await supabaseRestWithToken(
      "supplier_products",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      },
    );

    return NextResponse.redirect(
      new URL(`/suppliers/${id}?product_added=1`, request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(
        new URL("/login?error=session", request.url),
        303,
      );
    }

    return NextResponse.redirect(
      new URL(`/suppliers/${id}?error=product_save`, request.url),
      303,
    );
  }
}

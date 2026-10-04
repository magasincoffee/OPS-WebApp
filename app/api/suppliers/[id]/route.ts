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
  const supplierName = String(formData.get("supplier_name") ?? "").trim();

  if (!supplierName) {
    return NextResponse.redirect(
      new URL(`/suppliers/${id}?error=supplier_name`, request.url),
      303,
    );
  }

  const payload = {
    supplier_code: nullable(formData.get("supplier_code")),
    supplier_name: supplierName,
    contact_name: nullable(formData.get("contact_name")),
    phone: nullable(formData.get("phone")),
    address: nullable(formData.get("address")),
    notes: nullable(formData.get("notes")),
    is_active: formData.get("is_active") === "on",
  };

  try {
    await supabaseRestWithToken(
      `suppliers?id=eq.${encodeURIComponent(id)}`,
      accessToken,
      {
        method: "PATCH",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      },
    );

    return NextResponse.redirect(
      new URL(`/suppliers/${id}?saved=1`, request.url),
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
      new URL(`/suppliers/${id}?error=save`, request.url),
      303,
    );
  }
}

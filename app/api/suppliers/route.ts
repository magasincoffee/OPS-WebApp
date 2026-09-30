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

function redirectWithError(request: Request, code: string) {
  return NextResponse.redirect(
    new URL(`/suppliers?error=${encodeURIComponent(code)}`, request.url),
    303,
  );
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();

  if (!accessToken) {
    return NextResponse.redirect(
      new URL("/login?error=session", request.url),
      303,
    );
  }

  const formData = await request.formData();
  const supplierName = String(formData.get("supplier_name") ?? "").trim();

  if (!supplierName) {
    return redirectWithError(request, "supplier_name");
  }

  const payload = {
    supplier_code: nullable(formData.get("supplier_code")),
    supplier_name: supplierName,
    contact_name: nullable(formData.get("contact_name")),
    phone: nullable(formData.get("phone")),
    address: nullable(formData.get("address")),
    notes: nullable(formData.get("notes")),
    is_active: true,
  };

  try {
    const created = await supabaseRestWithToken<Array<{ id: string }>>(
      "suppliers",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      },
    );

    const supplierId = created[0]?.id;
    return NextResponse.redirect(
      new URL(supplierId ? `/suppliers/${supplierId}` : "/suppliers", request.url),
      303,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(
        new URL("/login?error=session", request.url),
        303,
      );
    }

    return redirectWithError(request, "save");
  }
}

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
    new URL(`/customers?error=${encodeURIComponent(code)}`, request.url),
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
  const displayName = String(formData.get("display_name") ?? "").trim();

  if (!displayName) {
    return redirectWithError(request, "display_name");
  }

  const payload = {
    customer_code: nullable(formData.get("customer_code")),
    display_name: displayName,
    brand_name: nullable(formData.get("brand_name")),
    company_name: nullable(formData.get("company_name")),
    contact_name: nullable(formData.get("contact_name")),
    phone: nullable(formData.get("phone")),
    address: nullable(formData.get("address")),
    notes: nullable(formData.get("notes")),
    is_active: true,
  };

  try {
    const created = await supabaseRestWithToken<Array<{ id: string }>>(
      "customers",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      },
    );

    const customerId = created[0]?.id;
    return NextResponse.redirect(
      new URL(customerId ? `/customers/${customerId}` : "/customers", request.url),
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

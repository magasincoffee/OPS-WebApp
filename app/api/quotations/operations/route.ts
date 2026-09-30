import { NextResponse } from "next/server";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

function redirectTo(request: Request, path: string) {
  return NextResponse.redirect(new URL(path, request.url), 303);
}

function numberOrNull(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

export async function POST(request: Request) {
  const accessToken = await getAccessToken();
  if (!accessToken) return redirectTo(request, "/login?error=session");

  const formData = await request.formData();
  const operation = String(formData.get("operation") ?? "").trim();

  try {
    if (operation === "create") {
      const quotationNumber = String(formData.get("quotation_number") ?? "").trim();
      const customerId = String(formData.get("customer_id") ?? "").trim();
      const validUntil = String(formData.get("valid_until") ?? "").trim();
      const currencyCode = String(formData.get("currency_code") ?? "VND").trim().toUpperCase();
      const notes = String(formData.get("notes") ?? "").trim();

      if (!quotationNumber || !customerId) {
        return redirectTo(request, "/quotations?error=required");
      }

      const id = await supabaseRestWithToken<string>("rpc/create_quotation", accessToken, {
        method: "POST",
        body: JSON.stringify({
          p_quotation_number: quotationNumber,
          p_customer_id: customerId,
          p_valid_until: validUntil || null,
          p_currency_code: currencyCode || "VND",
          p_notes: notes || null,
        }),
      });

      return redirectTo(request, `/quotations/${id}?action=created`);
    }

    if (operation === "add_item") {
      const quotationId = String(formData.get("quotation_id") ?? "").trim();
      const saleSource = String(formData.get("sale_source") ?? "").trim();
      const [variantId, packagingIdRaw = ""] = saleSource.split("|");
      const quantity = numberOrNull(formData.get("sale_quantity"));
      const discount = numberOrNull(formData.get("discount_amount")) ?? 0;
      const printMode = String(formData.get("print_mode") ?? "PLAIN").trim().toUpperCase();
      const printColors = numberOrNull(formData.get("print_color_count"));
      const printSpecification = String(formData.get("print_specification") ?? "").trim();
      const artworkReference = String(formData.get("artwork_reference") ?? "").trim();
      const dueDate = String(formData.get("requested_due_date") ?? "").trim();
      const notes = String(formData.get("notes") ?? "").trim();

      if (!quotationId || !variantId || quantity === null || Number.isNaN(quantity) || quantity <= 0) {
        return redirectTo(request, `/quotations/${quotationId}?error=item`);
      }
      if (discount === null || Number.isNaN(discount) || discount < 0) {
        return redirectTo(request, `/quotations/${quotationId}?error=discount`);
      }
      if (printColors !== null && (Number.isNaN(printColors) || !Number.isInteger(printColors))) {
        return redirectTo(request, `/quotations/${quotationId}?error=colors`);
      }

      await supabaseRestWithToken("rpc/add_quotation_item_priced", accessToken, {
        method: "POST",
        body: JSON.stringify({
          p_quotation_id: quotationId,
          p_product_variant_id: variantId,
          p_packaging_id: packagingIdRaw || null,
          p_sale_quantity: quantity,
          p_discount_amount: discount,
          p_print_mode: printMode,
          p_print_color_count: printColors,
          p_print_specification: printSpecification || null,
          p_artwork_reference: artworkReference || null,
          p_requested_due_date: dueDate || null,
          p_notes: notes || null,
        }),
      });

      return redirectTo(request, `/quotations/${quotationId}?action=item_added`);
    }

    if (operation === "remove_item") {
      const quotationId = String(formData.get("quotation_id") ?? "").trim();
      const itemId = String(formData.get("quotation_item_id") ?? "").trim();
      if (!quotationId || !itemId) return redirectTo(request, "/quotations?error=item");

      await supabaseRestWithToken("rpc/remove_quotation_item", accessToken, {
        method: "POST",
        body: JSON.stringify({ p_quotation_item_id: itemId }),
      });
      return redirectTo(request, `/quotations/${quotationId}?action=item_removed`);
    }

    if (operation === "status") {
      const quotationId = String(formData.get("quotation_id") ?? "").trim();
      const status = String(formData.get("status") ?? "").trim().toUpperCase();
      if (!quotationId || !status) return redirectTo(request, "/quotations?error=status");

      await supabaseRestWithToken("rpc/set_quotation_status", accessToken, {
        method: "POST",
        body: JSON.stringify({ p_quotation_id: quotationId, p_status: status }),
      });
      return redirectTo(request, `/quotations/${quotationId}?action=${status.toLowerCase()}`);
    }

    return redirectTo(request, "/quotations?error=operation");
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return redirectTo(request, "/login?error=session");
    }

    const quotationId = String(formData.get("quotation_id") ?? "").trim();
    const destination = quotationId ? `/quotations/${quotationId}` : "/quotations";
    return redirectTo(request, `${destination}?error=${encodeURIComponent(operation || "operation")}`);
  }
}

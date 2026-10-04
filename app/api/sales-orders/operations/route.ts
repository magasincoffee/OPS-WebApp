import { NextResponse } from "next/server";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";

function go(request: Request, path: string) {
  return NextResponse.redirect(new URL(path, request.url), 303);
}
function numeric(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

export async function POST(request: Request) {
  const token = await getAccessToken();
  if (!token) return go(request, "/login?error=session");
  const form = await request.formData();
  const operation = String(form.get("operation") ?? "").trim();

  try {
    if (operation === "create") {
      const orderNumber = String(form.get("order_number") ?? "").trim();
      const customerId = String(form.get("customer_id") ?? "").trim();
      const due = String(form.get("requested_due_date") ?? "").trim();
      const currency = String(form.get("currency_code") ?? "VND").trim().toUpperCase();
      const notes = String(form.get("notes") ?? "").trim();
      if (!orderNumber || !customerId) return go(request, "/sales-orders?error=required");
      const id = await supabaseRestWithToken<string>("rpc/create_sales_order_draft", token, {
        method: "POST",
        body: JSON.stringify({
          p_order_number: orderNumber,
          p_customer_id: customerId,
          p_requested_due_date: due || null,
          p_currency_code: currency || "VND",
          p_notes: notes || null,
        }),
      });
      return go(request, `/sales-orders/${id}?action=created`);
    }

    if (operation === "convert_quotation") {
      const quotationId = String(form.get("quotation_id") ?? "").trim();
      const orderNumber = String(form.get("order_number") ?? "").trim();
      const due = String(form.get("requested_due_date") ?? "").trim();
      const notes = String(form.get("notes") ?? "").trim();
      if (!quotationId || !orderNumber) return go(request, "/sales-orders?error=convert");
      const id = await supabaseRestWithToken<string>("rpc/convert_accepted_quotation_to_sales_order", token, {
        method: "POST",
        body: JSON.stringify({
          p_quotation_id: quotationId,
          p_order_number: orderNumber,
          p_requested_due_date: due || null,
          p_notes: notes || null,
        }),
      });
      return go(request, `/sales-orders/${id}?action=converted`);
    }

    if (operation === "add_item") {
      const orderId = String(form.get("sales_order_id") ?? "").trim();
      const source = String(form.get("sale_source") ?? "").trim();
      const [variantId, packageId = ""] = source.split("|");
      const quantity = numeric(form.get("sale_quantity"));
      const discount = numeric(form.get("discount_amount")) ?? 0;
      const printMode = String(form.get("print_mode") ?? "PLAIN").trim().toUpperCase();
      const colors = numeric(form.get("print_color_count"));
      const specification = String(form.get("print_specification") ?? "").trim();
      const artwork = String(form.get("artwork_reference") ?? "").trim();
      const due = String(form.get("requested_due_date") ?? "").trim();
      const notes = String(form.get("notes") ?? "").trim();
      if (!orderId || !variantId || quantity === null || Number.isNaN(quantity) || quantity <= 0) {
        return go(request, `/sales-orders/${orderId}?error=item`);
      }
      if (discount === null || Number.isNaN(discount) || discount < 0) {
        return go(request, `/sales-orders/${orderId}?error=discount`);
      }
      if (colors !== null && (Number.isNaN(colors) || !Number.isInteger(colors))) {
        return go(request, `/sales-orders/${orderId}?error=colors`);
      }
      await supabaseRestWithToken("rpc/add_sales_order_item_priced", token, {
        method: "POST",
        body: JSON.stringify({
          p_sales_order_id: orderId,
          p_product_variant_id: variantId,
          p_packaging_id: packageId || null,
          p_sale_quantity: quantity,
          p_discount_amount: discount,
          p_print_mode: printMode,
          p_print_color_count: colors,
          p_print_specification: specification || null,
          p_artwork_reference: artwork || null,
          p_requested_due_date: due || null,
          p_notes: notes || null,
        }),
      });
      return go(request, `/sales-orders/${orderId}?action=item_added`);
    }

    if (operation === "remove_item") {
      const orderId = String(form.get("sales_order_id") ?? "").trim();
      const itemId = String(form.get("sales_order_item_id") ?? "").trim();
      if (!orderId || !itemId) return go(request, "/sales-orders?error=item");
      await supabaseRestWithToken("rpc/remove_sales_order_item", token, {
        method: "POST",
        body: JSON.stringify({ p_sales_order_item_id: itemId }),
      });
      return go(request, `/sales-orders/${orderId}?action=item_removed`);
    }

    if (operation === "status") {
      const orderId = String(form.get("sales_order_id") ?? "").trim();
      const status = String(form.get("status") ?? "").trim().toUpperCase();
      if (!orderId || !status) return go(request, "/sales-orders?error=status");
      await supabaseRestWithToken("rpc/set_sales_order_status", token, {
        method: "POST",
        body: JSON.stringify({ p_sales_order_id: orderId, p_status: status }),
      });
      return go(request, `/sales-orders/${orderId}?action=${status.toLowerCase()}`);
    }

    return go(request, "/sales-orders?error=operation");
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) return go(request, "/login?error=session");
    const orderId = String(form.get("sales_order_id") ?? "").trim();
    return go(request, orderId ? `/sales-orders/${orderId}?error=${encodeURIComponent(operation)}` : `/sales-orders?error=${encodeURIComponent(operation || "operation")}`);
  }
}

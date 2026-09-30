import { NextResponse } from "next/server";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";

function go(request: Request, path: string) {
  return NextResponse.redirect(new URL(path, request.url), 303);
}

export async function POST(request: Request) {
  const token = await getAccessToken();
  if (!token) return go(request, "/login?error=session");
  const form = await request.formData();
  const operation = String(form.get("operation") ?? "").trim();

  try {
    if (operation === "create") {
      const jobNumber = String(form.get("job_number") ?? "").trim();
      const salesOrderItemId = String(form.get("sales_order_item_id") ?? "").trim();
      const notes = String(form.get("notes") ?? "").trim();
      if (!jobNumber || !salesOrderItemId) return go(request, "/print-jobs?error=required");
      const id = await supabaseRestWithToken<string>("rpc/create_print_job_from_requirement", token, {
        method: "POST",
        body: JSON.stringify({ p_job_number: jobNumber, p_sales_order_item_id: salesOrderItemId, p_notes: notes || null }),
      });
      return go(request, `/print-jobs/${id}?action=created`);
    }

    if (operation === "status") {
      const printJobId = String(form.get("print_job_id") ?? "").trim();
      const status = String(form.get("status") ?? "").trim().toUpperCase();
      const note = String(form.get("note") ?? "").trim();
      if (!printJobId || !status) return go(request, "/print-jobs?error=status");
      await supabaseRestWithToken("rpc/set_print_job_status", token, {
        method: "POST",
        body: JSON.stringify({ p_print_job_id: printJobId, p_status: status, p_note: note || null }),
      });
      return go(request, `/print-jobs/${printJobId}?action=${status.toLowerCase()}`);
    }

    return go(request, "/print-jobs?error=operation");
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) return go(request, "/login?error=session");
    const printJobId = String(form.get("print_job_id") ?? "").trim();
    return go(request, printJobId ? `/print-jobs/${printJobId}?error=${encodeURIComponent(operation || "operation")}` : `/print-jobs?error=${encodeURIComponent(operation || "operation")}`);
  }
}

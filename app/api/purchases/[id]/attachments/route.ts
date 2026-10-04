import { NextResponse } from "next/server";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

type Attachment = { id: string };

function safeFileName(name: string) {
  const cleaned = name.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/-+/g, "-");
  return cleaned.slice(0, 120) || "document";
}

export async function POST(request: Request, context: RouteContext) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  }

  const { id } = await context.params;
  const formData = await request.formData();
  const file = formData.get("file");
  const kind = String(formData.get("attachment_kind") ?? "DOCUMENT").trim();
  const paymentId = String(formData.get("purchase_payment_id") ?? "").trim();

  if (!(file instanceof File) || file.size <= 0 || !["DOCUMENT", "PAYMENT_EVIDENCE"].includes(kind)) {
    return NextResponse.redirect(new URL(`/purchases/${id}?error=attachment_required`, request.url), 303);
  }

  const storagePath = `purchase-orders/${id}/${crypto.randomUUID()}-${safeFileName(file.name)}`;

  try {
    const attachments = await supabaseRestWithToken<Attachment[]>(
      "attachments",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          linked_entity_type: "PURCHASE_ORDER",
          linked_entity_id: id,
          attachment_kind: kind,
          storage_bucket: "ops-attachments",
          storage_path: storagePath,
          original_file_name: file.name,
          media_type: file.type || null,
          size_bytes: file.size,
          metadata: paymentId ? { purchase_payment_id: paymentId } : {},
          uploaded_by_user_id: null,
        }),
      },
    );

    const attachment = attachments[0];
    if (!attachment) {
      throw new Error("Attachment metadata was not created");
    }

    const { url, publishableKey } = getSupabasePublicConfig();
    const encodedPath = storagePath.split("/").map(encodeURIComponent).join("/");
    const uploadResponse = await fetch(
      `${url}/storage/v1/object/ops-attachments/${encodedPath}`,
      {
        method: "POST",
        headers: {
          apikey: publishableKey,
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": file.type || "application/octet-stream",
          "x-upsert": "false",
        },
        body: await file.arrayBuffer(),
        cache: "no-store",
      },
    );

    if (!uploadResponse.ok) {
      throw new Error(`Storage upload failed: ${await uploadResponse.text()}`);
    }

    if (kind === "PAYMENT_EVIDENCE" && paymentId) {
      await supabaseRestWithToken(
        `purchase_payments?id=eq.${encodeURIComponent(paymentId)}&purchase_order_id=eq.${encodeURIComponent(id)}`,
        accessToken,
        {
          method: "PATCH",
          headers: { Prefer: "return=minimal" },
          body: JSON.stringify({ evidence_attachment_id: attachment.id }),
        },
      );
    }

    return NextResponse.redirect(new URL(`/purchases/${id}?attachment_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/purchases/${id}?error=attachment_save`, request.url), 303);
  }
}

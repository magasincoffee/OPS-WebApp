import { NextResponse } from "next/server";
import { getCurrentRoles } from "@/lib/auth/roles";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRestWithToken,
} from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };
type UserRow = { id: string };
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

  if (!(file instanceof File) || file.size <= 0) {
    return NextResponse.redirect(new URL(`/receipts/${id}?error=attachment_required`, request.url), 303);
  }

  try {
    const roles = await getCurrentRoles();
    let uploaderId: string | null = null;

    if (!roles.has("OWNER_ADMIN")) {
      const self = await supabaseRestWithToken<UserRow[]>(
        "users?select=id&limit=1",
        accessToken,
      );
      uploaderId = self[0]?.id ?? null;
      if (!uploaderId) {
        return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
      }
    }

    const storagePath = `goods-receipts/${id}/${crypto.randomUUID()}-${safeFileName(file.name)}`;

    const attachments = await supabaseRestWithToken<Attachment[]>(
      "attachments",
      accessToken,
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          linked_entity_type: "GOODS_RECEIPT",
          linked_entity_id: id,
          attachment_kind: "DOCUMENT",
          storage_bucket: "ops-attachments",
          storage_path: storagePath,
          original_file_name: file.name,
          media_type: file.type || null,
          size_bytes: file.size,
          metadata: {},
          uploaded_by_user_id: uploaderId,
        }),
      },
    );

    const attachment = attachments[0];
    if (!attachment) throw new Error("Attachment metadata was not created");

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

    return NextResponse.redirect(new URL(`/receipts/${id}?attachment_saved=1`, request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    }
    return NextResponse.redirect(new URL(`/receipts/${id}?error=attachment_save`, request.url), 303);
  }
}

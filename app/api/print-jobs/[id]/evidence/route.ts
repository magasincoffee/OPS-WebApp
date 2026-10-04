import { NextResponse } from "next/server";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";

type RouteContext = { params: Promise<{ id: string }> };

function safeFileName(name: string) {
  const cleaned = name.replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/-+/g, "-");
  return cleaned.slice(0, 120) || "production-evidence";
}

export async function POST(request: Request, context: RouteContext) {
  const token = await getAccessToken();
  if (!token) return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
  const { id } = await context.params;
  const form = await request.formData();
  const file = form.get("file");
  if (!(file instanceof File) || file.size <= 0) {
    return NextResponse.redirect(new URL("/print-jobs/" + id + "?error=evidence_required", request.url), 303);
  }
  const storagePath = "print-jobs/" + id + "/" + crypto.randomUUID() + "-" + safeFileName(file.name);
  try {
    await supabaseRestWithToken("rpc/create_print_job_evidence_attachment", token, {
      method: "POST",
      body: JSON.stringify({
        p_print_job_id: id,
        p_storage_path: storagePath,
        p_original_file_name: file.name,
        p_media_type: file.type || null,
        p_size_bytes: file.size,
      }),
    });
    const { url, publishableKey } = getSupabasePublicConfig();
    const encodedPath = storagePath.split("/").map(encodeURIComponent).join("/");
    const response = await fetch(url + "/storage/v1/object/ops-attachments/" + encodedPath, {
      method: "POST",
      headers: {
        apikey: publishableKey,
        Authorization: "Bearer " + token,
        "Content-Type": file.type || "application/octet-stream",
        "x-upsert": "false",
      },
      body: await file.arrayBuffer(),
      cache: "no-store",
    });
    if (!response.ok) throw new Error("Storage upload failed: " + await response.text());
    return NextResponse.redirect(new URL("/print-jobs/" + id + "?action=evidence-uploaded", request.url), 303);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) return NextResponse.redirect(new URL("/login?error=session", request.url), 303);
    return NextResponse.redirect(new URL("/print-jobs/" + id + "?error=evidence_upload", request.url), 303);
  }
}
import { NextResponse } from "next/server";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";
type RouteContext={params:Promise<{id:string}>};
type Attachment={storage_bucket:string;storage_path:string;original_file_name:string;media_type:string|null};
export async function GET(request:Request,context:RouteContext){
  const token=await getAccessToken(); if(!token)return NextResponse.redirect(new URL("/login?error=session",request.url),303);
  const {id}=await context.params;
  try{
    const rows=await supabaseRestWithToken<Attachment[]>("attachments?id=eq."+encodeURIComponent(id)+"&linked_entity_type=eq.CUSTOMER_PAYMENT&attachment_kind=eq.PAYMENT_EVIDENCE&select=storage_bucket,storage_path,original_file_name,media_type",token);
    const attachment=rows[0]; if(!attachment)return new NextResponse("Not found",{status:404});
    const {url,publishableKey}=getSupabasePublicConfig(); const encodedPath=attachment.storage_path.split("/").map(encodeURIComponent).join("/");
    const response=await fetch(url+"/storage/v1/object/authenticated/"+encodeURIComponent(attachment.storage_bucket)+"/"+encodedPath,{headers:{apikey:publishableKey,Authorization:"Bearer "+token},cache:"no-store"});
    if(!response.ok)return new NextResponse("Unable to read evidence",{status:response.status});
    const body=await response.arrayBuffer(); const safeName=attachment.original_file_name.replace(/[\r\n"]/g,"_");
    return new NextResponse(body,{status:200,headers:{"Content-Type":attachment.media_type||"application/octet-stream","Content-Disposition":"attachment; filename=\""+safeName+"\"","Cache-Control":"private, no-store"}});
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)return NextResponse.redirect(new URL("/login?error=session",request.url),303);
    return new NextResponse("Unable to read evidence",{status:500});
  }
}

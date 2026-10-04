import { NextResponse } from "next/server";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";

function go(request: Request, path: string) {
  return NextResponse.redirect(new URL(path, request.url), 303);
}

export async function POST(request: Request) {
  const token=await getAccessToken();
  if(!token) return go(request,"/login?error=session");
  const form=await request.formData();
  const operation=String(form.get("operation")??"").trim();

  try{
    if(operation==="create"){
      const deliveryNumber=String(form.get("delivery_number")??"").trim();
      const salesOrderId=String(form.get("sales_order_id")??"").trim();
      const consigneeName=String(form.get("consignee_name")??"").trim();
      if(!deliveryNumber||!salesOrderId||!consigneeName) return go(request,"/deliveries?error=required");
      const id=await supabaseRestWithToken<string>("rpc/create_delivery",token,{
        method:"POST",
        body:JSON.stringify({
          p_delivery_number:deliveryNumber,
          p_sales_order_id:salesOrderId,
          p_consignee_name:consigneeName,
          p_consignee_phone:String(form.get("consignee_phone")??"").trim()||null,
          p_consignee_address:String(form.get("consignee_address")??"").trim()||null,
          p_parcel_info:String(form.get("parcel_info")??"").trim()||null,
          p_carrier_note:String(form.get("carrier_note")??"").trim()||null,
          p_delivery_reference:String(form.get("delivery_reference")??"").trim()||null,
          p_notes:String(form.get("notes")??"").trim()||null,
        }),
      });
      return go(request,`/deliveries/${id}?action=created`);
    }

    if(operation==="update_details"){
      const deliveryId=String(form.get("delivery_id")??"").trim();
      const consigneeName=String(form.get("consignee_name")??"").trim();
      if(!deliveryId||!consigneeName) return go(request,`/deliveries/${deliveryId}?error=required`);
      await supabaseRestWithToken("rpc/update_delivery_details",token,{
        method:"POST",
        body:JSON.stringify({
          p_delivery_id:deliveryId,
          p_consignee_name:consigneeName,
          p_consignee_phone:String(form.get("consignee_phone")??"").trim()||null,
          p_consignee_address:String(form.get("consignee_address")??"").trim()||null,
          p_parcel_info:String(form.get("parcel_info")??"").trim()||null,
          p_carrier_note:String(form.get("carrier_note")??"").trim()||null,
          p_delivery_reference:String(form.get("delivery_reference")??"").trim()||null,
          p_notes:String(form.get("notes")??"").trim()||null,
        }),
      });
      return go(request,`/deliveries/${deliveryId}?action=updated`);
    }

    if(operation==="status"){
      const deliveryId=String(form.get("delivery_id")??"").trim();
      const status=String(form.get("status")??"").trim().toUpperCase();
      const dispatchDate=String(form.get("dispatch_date")??"").trim();
      if(!deliveryId||!status) return go(request,"/deliveries?error=status");
      await supabaseRestWithToken("rpc/set_delivery_status",token,{
        method:"POST",
        body:JSON.stringify({
          p_delivery_id:deliveryId,
          p_status:status,
          p_dispatch_date:dispatchDate||null,
        }),
      });
      return go(request,`/deliveries/${deliveryId}?action=${status.toLowerCase()}`);
    }

    return go(request,"/deliveries?error=operation");
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401) return go(request,"/login?error=session");
    const deliveryId=String(form.get("delivery_id")??"").trim();
    return go(request,deliveryId?`/deliveries/${deliveryId}?error=${encodeURIComponent(operation||"operation")}`:`/deliveries?error=${encodeURIComponent(operation||"operation")}`);
  }
}

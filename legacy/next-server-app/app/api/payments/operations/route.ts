import { NextResponse } from "next/server";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";

function go(request:Request,path:string){return NextResponse.redirect(new URL(path,request.url),303);}
function nullable(value:FormDataEntryValue|null){const v=String(value??"").trim();return v||null;}

export async function POST(request:Request){
  const token=await getAccessToken(); if(!token)return go(request,"/login?error=session");
  const form=await request.formData(); const operation=String(form.get("operation")??"").trim();
  try{
    if(operation==="record"){
      const salesOrderId=String(form.get("sales_order_id")??"").trim();
      const amount=Number(String(form.get("amount")??"").trim());
      const paymentDate=String(form.get("payment_date")??"").trim();
      const paymentMethod=String(form.get("payment_method")??"").trim();
      if(!salesOrderId||!Number.isFinite(amount)||amount<=0||!paymentDate||!paymentMethod)return go(request,"/payments?error=required");
      await supabaseRestWithToken("rpc/record_customer_payment",token,{method:"POST",body:JSON.stringify({p_sales_order_id:salesOrderId,p_amount:amount,p_payment_date:paymentDate,p_payment_method:paymentMethod,p_reference:nullable(form.get("reference")),p_note:nullable(form.get("note"))})});
      return go(request,"/payments?action=recorded");
    }
    if(operation==="void"){
      const id=String(form.get("customer_payment_id")??"").trim(); if(!id)return go(request,"/payments?error=void");
      await supabaseRestWithToken("rpc/void_customer_payment",token,{method:"POST",body:JSON.stringify({p_customer_payment_id:id})});
      return go(request,"/payments?action=voided");
    }
    return go(request,"/payments?error=operation");
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)return go(request,"/login?error=session");
    return go(request,"/payments?error="+encodeURIComponent(operation||"operation"));
  }
}

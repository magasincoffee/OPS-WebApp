import { NextResponse } from "next/server";
import { getAccessToken, SupabaseRestError, supabaseRestWithToken } from "@/lib/supabase/rest";

function go(request:Request,path:string){return NextResponse.redirect(new URL(path,request.url),303);}
function nullable(value:FormDataEntryValue|null){const v=String(value??"").trim();return v||null;}
function dueAt(value:FormDataEntryValue|null){const v=String(value??"").trim();return v?new Date(v+"T23:59:59+07:00").toISOString():null;}

export async function POST(request:Request){
  const token=await getAccessToken(); if(!token)return go(request,"/login?error=session");
  const form=await request.formData(); const operation=String(form.get("operation")??"").trim();
  try{
    if(operation==="create"){
      const taskType=String(form.get("task_type")??"").trim();
      const linkedType=nullable(form.get("linked_entity_type"));
      const linkedId=nullable(form.get("linked_entity_id"));
      const assignee=nullable(form.get("assignee_user_id"));
      const priority=String(form.get("priority")??"NORMAL").trim();
      if(!taskType)return go(request,"/tasks?error=required");
      await supabaseRestWithToken("rpc/create_operational_task",token,{method:"POST",body:JSON.stringify({p_task_type:taskType,p_linked_entity_type:linkedType,p_linked_entity_id:linkedId,p_assignee_user_id:assignee,p_due_at:dueAt(form.get("due_date")),p_priority:priority,p_notes:nullable(form.get("notes"))})});
      return go(request,"/tasks?action=created");
    }
    if(operation==="manage"){
      const id=String(form.get("task_id")??"").trim(); if(!id)return go(request,"/tasks?error=task");
      await supabaseRestWithToken("rpc/manage_operational_task",token,{method:"POST",body:JSON.stringify({p_task_id:id,p_assignee_user_id:nullable(form.get("assignee_user_id")),p_due_at:dueAt(form.get("due_date")),p_priority:String(form.get("priority")??"NORMAL").trim(),p_notes:nullable(form.get("notes"))})});
      return go(request,"/tasks?action=managed");
    }
    if(operation==="execute"){
      const id=String(form.get("task_id")??"").trim(); const status=String(form.get("status")??"").trim();
      if(!id||!status)return go(request,"/tasks?error=execution");
      await supabaseRestWithToken("rpc/update_operational_task_execution",token,{method:"POST",body:JSON.stringify({p_task_id:id,p_status:status,p_notes:nullable(form.get("notes"))})});
      return go(request,"/tasks?action="+encodeURIComponent(status.toLowerCase()));
    }
    if(operation==="cancel"){
      const id=String(form.get("task_id")??"").trim(); if(!id)return go(request,"/tasks?error=cancel");
      await supabaseRestWithToken("rpc/cancel_operational_task",token,{method:"POST",body:JSON.stringify({p_task_id:id,p_note:nullable(form.get("note"))})});
      return go(request,"/tasks?action=cancelled");
    }
    return go(request,"/tasks?error=operation");
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)return go(request,"/login?error=session");
    return go(request,"/tasks?error="+encodeURIComponent(operation||"operation"));
  }
}

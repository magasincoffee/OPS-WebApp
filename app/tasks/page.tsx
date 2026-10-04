import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Task={
  task_id:string;task_type:string;linked_entity_type:string|null;linked_entity_id:string|null;
  assignee_user_id:string|null;due_at:string|null;status:string;priority:string;notes:string|null;
  completed_at:string|null;created_at:string;updated_at:string;is_overdue:boolean;
};
type Assignee={user_id:string;display_name:string|null;role_codes:string[]};

function day(value:string|null){
  if(!value)return "—";
  return new Intl.DateTimeFormat("vi-VN",{dateStyle:"medium",timeZone:"Asia/Ho_Chi_Minh"}).format(new Date(value));
}
function dateInput(value:string|null){
  if(!value)return "";
  return new Intl.DateTimeFormat("en-CA",{year:"numeric",month:"2-digit",day:"2-digit",timeZone:"Asia/Ho_Chi_Minh"}).format(new Date(value));
}

export default async function TasksPage(){
  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const isOperational=isOwner||roles.has("SALES")||roles.has("ACCOUNTING")||roles.has("WAREHOUSE")||roles.has("PRINTER_PRODUCTION");
  if(!isOperational)redirect("/");

  let tasks:Task[]=[]; let assignees:Assignee[]=[];
  try{
    tasks=await supabaseRest<Task[]>("operational_task_queue?select=task_id,task_type,linked_entity_type,linked_entity_id,assignee_user_id,due_at,status,priority,notes,completed_at,created_at,updated_at,is_overdue&order=created_at.desc&limit=1000");
    if(isOwner)assignees=await supabaseRest<Assignee[]>("rpc/task_assignee_directory",{method:"POST",body:"{}"});
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");
    throw error;
  }

  const assigneeById=new Map(assignees.map(row=>[row.user_id,row]));
  const open=tasks.filter(row=>!["DONE","CANCELLED"].includes(row.status));
  const overdue=open.filter(row=>row.is_overdue);
  const blocked=open.filter(row=>row.status==="BLOCKED");

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-061</p><h1>Operational Tasks</h1><p className="muted">{isOwner?"Owner/Admin assignment board":"My assigned operational work"}</p></div><div className="hero-actions"><Link href="/" className="button button-secondary">Dashboard</Link></div></header>

    <section className="metric-grid">
      <article className="metric-card"><span>Open</span><strong>{open.length}</strong></article>
      <article className="metric-card"><span>Overdue</span><strong>{overdue.length}</strong></article>
      <article className="metric-card"><span>Blocked</span><strong>{blocked.length}</strong></article>
      <article className="metric-card"><span>Completed</span><strong>{tasks.filter(row=>row.status==="DONE").length}</strong></article>
    </section>

    {isOwner?<section className="content-card"><h2>Create operational task</h2><form action="/api/tasks/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="create"/><div className="form-row"><label>Task type *<select name="task_type" required defaultValue="ORDER_OPERATION"><option value="PRINT_JOB">Print job</option><option value="WAREHOUSE_PREPARATION">Warehouse preparation</option><option value="WAREHOUSE_ISSUE">Warehouse issue</option><option value="ACCOUNTING_FOLLOW_UP">Accounting follow-up</option><option value="ORDER_OPERATION">Other order operation</option></select></label><label>Priority<select name="priority" defaultValue="NORMAL"><option>LOW</option><option>NORMAL</option><option>HIGH</option><option>URGENT</option></select></label></div><div className="form-row"><label>Assignee<select name="assignee_user_id" defaultValue=""><option value="">Unassigned</option>{assignees.map(user=><option key={user.user_id} value={user.user_id}>{user.display_name??user.user_id} · {user.role_codes.join("/")}</option>)}</select></label><label>Due date<input type="date" name="due_date"/></label></div><div className="form-row"><label>Linked entity type<select name="linked_entity_type" defaultValue=""><option value="">None</option><option value="SALES_ORDER">Sales order</option><option value="PRINT_JOB">Print job</option><option value="INVENTORY_RESERVATION">Inventory reservation</option><option value="CUSTOMER_PAYMENT">Customer payment</option><option value="DELIVERY">Delivery</option></select></label><label>Linked entity UUID<input name="linked_entity_id" placeholder="UUID"/></label></div><label>Notes<textarea name="notes" rows={2}/></label><button type="submit" className="button button-primary">Create task</button></form></section>:null}

    <section className="content-card"><h2>{isOwner?"Task board":"My tasks"}</h2><div className="table-wrap"><table><thead><tr><th>Task / Link</th><th>Priority / Due</th>{isOwner?<th>Assignee</th>:null}<th>Status</th><th>Notes / Actions</th></tr></thead><tbody>{tasks.map(task=>{const assignee=task.assignee_user_id?assigneeById.get(task.assignee_user_id):undefined;return <tr key={task.task_id}><td><strong>{task.task_type}</strong><div className="subtle">{task.linked_entity_type?task.linked_entity_type+" · "+task.linked_entity_id:"No linked entity"}</div></td><td><strong>{task.priority}</strong><div className="subtle">{day(task.due_at)}{task.is_overdue?" · OVERDUE":""}</div></td>{isOwner?<td>{assignee?.display_name??task.assignee_user_id??"Unassigned"}{assignee?<div className="subtle">{assignee.role_codes.join(" / ")}</div>:null}</td>:null}<td><strong>{task.status}</strong>{task.completed_at?<div className="subtle">Done {day(task.completed_at)}</div>:null}</td><td><div className="form-stack">{!["DONE","CANCELLED"].includes(task.status)||isOwner?<form action="/api/tasks/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="execute"/><input type="hidden" name="task_id" value={task.task_id}/><textarea name="notes" rows={2} defaultValue={task.notes??""} placeholder="Execution note"/><div className="hero-actions">{task.status==="OPEN"?<button type="submit" name="status" value="IN_PROGRESS" className="button button-primary">Start</button>:null}{task.status!=="BLOCKED"&&task.status!=="DONE"&&task.status!=="CANCELLED"?<button type="submit" name="status" value="BLOCKED" className="button button-secondary">Block</button>:null}{task.status==="BLOCKED"?<button type="submit" name="status" value="IN_PROGRESS" className="button button-primary">Resume</button>:null}{task.status!=="DONE"&&task.status!=="CANCELLED"?<button type="submit" name="status" value="DONE" className="button button-primary">Complete</button>:null}{isOwner&&task.status==="DONE"?<button type="submit" name="status" value="OPEN" className="button button-secondary">Reopen</button>:null}</div></form>:<p className="subtle">{task.notes??"—"}</p>}{isOwner&&!["DONE","CANCELLED"].includes(task.status)?<><form action="/api/tasks/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="manage"/><input type="hidden" name="task_id" value={task.task_id}/><select name="assignee_user_id" defaultValue={task.assignee_user_id??""}><option value="">Unassigned</option>{assignees.map(user=><option key={user.user_id} value={user.user_id}>{user.display_name??user.user_id} · {user.role_codes.join("/")}</option>)}</select><div className="form-row"><input type="date" name="due_date" defaultValue={dateInput(task.due_at)}/><select name="priority" defaultValue={task.priority}><option>LOW</option><option>NORMAL</option><option>HIGH</option><option>URGENT</option></select></div><input name="notes" defaultValue={task.notes??""} placeholder="Management note"/><button type="submit" className="button button-secondary">Save assignment</button></form><form action="/api/tasks/operations" method="post"><input type="hidden" name="operation" value="cancel"/><input type="hidden" name="task_id" value={task.task_id}/><input name="note" placeholder="Cancellation reason"/><button type="submit" className="button button-secondary">Cancel task</button></form></>:null}</div></td></tr>;})}{tasks.length===0?<tr><td colSpan={isOwner?5:4} className="empty-state">Không có operational task.</td></tr>:null}</tbody></table></div></section>
  </main>;
}

import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Job={print_job_id:string;job_number:string;order_number:string;customer_name:string;sku_code:string;product_name:string;product_type_snapshot:string|null;quantity_base_units:number;print_color_count:number;print_specification:string|null;artwork_reference:string|null;due_date:string;assignee_user_id:string|null;status:string;qc_state:string;accepted_at:string|null;started_at:string|null;notes:string|null;};
type Assignee={user_id:string;display_name:string|null;};
type Evidence={id:string;original_file_name:string;media_type:string|null;size_bytes:number|null;created_at:string;uploaded_by_user_id:string|null;};
type PageProps={params:Promise<{id:string}>;searchParams:Promise<{action?:string;error?:string}>};

function day(value:string){return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(`${value}T00:00:00`));}
function qty(value:number){return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));}

export default async function PrintJobDetailPage({params,searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const isProduction=roles.has("PRINTER_PRODUCTION");
  if(!isOwner&&!isProduction) redirect("/");
  const {id}=await params; const state=await searchParams;

  let rows:Job[]; let assignees:Assignee[]=[]; let evidence:Evidence[]=[];
  try{
    rows=await supabaseRest<Job[]>("rpc/print_job_tracking",{method:"POST",body:JSON.stringify({p_print_job_id:id})});
    evidence=await supabaseRest<Evidence[]>("attachments?linked_entity_type=eq.PRINT_JOB&linked_entity_id=eq."+encodeURIComponent(id)+"&attachment_kind=eq.PRODUCTION_EVIDENCE&select=id,original_file_name,media_type,size_bytes,created_at,uploaded_by_user_id&order=created_at.desc");
    if(isOwner) assignees=await supabaseRest<Assignee[]>("rpc/production_assignee_directory",{method:"POST",body:"{}"});
  }
  catch(error){if(error instanceof SupabaseRestError&&error.status===401) redirect("/login?error=session"); throw error;}
  const job=rows[0]; if(!job) notFound();

  const actions=job.status==="WAITING"?["ACCEPTED","CANCELLED"]:job.status==="ACCEPTED"?["IN_PROGRESS","CANCELLED"]:job.status==="IN_PROGRESS"?["WAITING_QC","CANCELLED"]:[];

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-042</p><h1>{job.job_number}</h1><p className="muted">{job.order_number} · {job.customer_name} · {job.status}</p></div><div className="hero-actions"><Link href="/production" className="button button-secondary">Mobile Queue</Link><Link href="/print-jobs" className="button button-secondary">Print Jobs</Link><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link></div></header>
    {state.action?<section className="content-card"><p className="permission-note">Print-job action completed: {state.action}.</p></section>:null}
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất thao tác ({state.error}).</p></section>:null}

    <section className="metric-grid"><article className="metric-card"><span>Status</span><strong>{job.status}</strong></article><article className="metric-card"><span>QC</span><strong>{job.qc_state}</strong></article><article className="metric-card"><span>Due</span><strong className="metric-small">{day(job.due_date)}</strong></article><article className="metric-card"><span>Assignment</span><strong className="metric-small">{job.assignee_user_id?(assignees.find(user=>user.user_id===job.assignee_user_id)?.display_name??"ASSIGNED"):"UNASSIGNED"}</strong></article></section>

    <section className="dashboard-grid"><article className="content-card"><h2>Immutable production snapshot</h2><p><strong>SKU:</strong> {job.sku_code} · {job.product_name}</p><p><strong>Product type:</strong> {job.product_type_snapshot??"—"}</p><p><strong>Quantity:</strong> {qty(job.quantity_base_units)}</p><p><strong>Colors:</strong> {job.print_color_count}</p><p><strong>Specification:</strong> {job.print_specification??"—"}</p><p><strong>Artwork:</strong> {job.artwork_reference??"—"}</p><p><strong>Notes:</strong> {job.notes??"—"}</p></article><aside className="content-card"><h2>Execution boundary</h2><p className="muted">OPS-042 yêu cầu PRODUCTION_EVIDENCE trước QC. PASS hoàn tất job; FAIL trả job về IN_PROGRESS để rework. Assignment vẫn bị khóa sau ACCEPTED.</p><p><strong>Accepted:</strong> {job.accepted_at?"YES":"NO"}</p><p><strong>Started:</strong> {job.started_at?"YES":"NO"}</p></aside></section>

    {isOwner&&job.status==="WAITING"?<section className="content-card"><h2>Production assignment</h2><p className="muted">Chỉ active PRINTER_PRODUCTION user. Assignment khóa ngay khi worker ACCEPTED.</p><form action="/api/print-jobs/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="assignment"/><input type="hidden" name="print_job_id" value={job.print_job_id}/><label>Assignee<select name="assignee_user_id" defaultValue={job.assignee_user_id??""}><option value="">Unassigned</option>{assignees.map(user=><option key={user.user_id} value={user.user_id}>{user.display_name??user.user_id}</option>)}</select></label><label>Note<input name="note" placeholder="Assignment note"/></label><button type="submit" className="button button-primary">Save assignment</button></form></section>:null}

    <section className="content-card"><h2>QC evidence</h2><p className="muted">Private evidence trong ops-attachments; chỉ Owner/Admin hoặc assigned production user có quyền theo RLS.</p>{job.status==="IN_PROGRESS"||job.status==="WAITING_QC"?<form action={"/api/print-jobs/"+job.print_job_id+"/evidence"} method="post" encType="multipart/form-data" className="form-stack"><label>Upload production/QC evidence<input type="file" name="file" required/></label><button type="submit" className="button button-secondary">Upload evidence</button></form>:null}<div className="table-wrap"><table><thead><tr><th>Evidence</th><th>Created</th><th>Download</th></tr></thead><tbody>{evidence.map(item=><tr key={item.id}><td>{item.original_file_name}</td><td>{new Intl.DateTimeFormat("vi-VN",{dateStyle:"short",timeStyle:"short"}).format(new Date(item.created_at))}</td><td><Link href={"/api/print-jobs/evidence/"+item.id} className="button button-secondary">Download</Link></td></tr>)}{evidence.length===0?<tr><td colSpan={3} className="empty-state">Chưa có production evidence.</td></tr>:null}</tbody></table></div>{job.status==="WAITING_QC"?<form action="/api/print-jobs/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="qc"/><input type="hidden" name="print_job_id" value={job.print_job_id}/><label>Evidence<select name="evidence_attachment_id" required defaultValue=""><option value="" disabled>Chọn evidence</option>{evidence.map(item=><option key={item.id} value={item.id}>{item.original_file_name}</option>)}</select></label><label>QC note<input name="note" placeholder="QC note"/></label><div className="hero-actions"><button type="submit" name="qc_result" value="PASSED" className="button button-primary">QC PASS & Complete</button><button type="submit" name="qc_result" value="FAILED" className="button button-secondary">QC FAIL & Rework</button></div></form>:null}</section>

    {actions.length>0?<section className="content-card"><h2>Production lifecycle</h2><p className="muted">WAITING → ACCEPTED → IN_PROGRESS → WAITING_QC.</p><div className="hero-actions">{actions.map(action=><form action="/api/print-jobs/operations" method="post" key={action}><input type="hidden" name="operation" value="status"/><input type="hidden" name="print_job_id" value={job.print_job_id}/><input type="hidden" name="status" value={action}/><input name="note" placeholder="Transition note"/><button type="submit" className={action==="CANCELLED"?"button button-secondary":"button button-primary"}>{action}</button></form>)}</div></section>:null}
  </main>;
}

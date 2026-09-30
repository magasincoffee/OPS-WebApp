import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Job={print_job_id:string;job_number:string;order_number:string;customer_name:string;sku_code:string;product_name:string;product_type_snapshot:string|null;quantity_base_units:number;print_color_count:number;print_specification:string|null;artwork_reference:string|null;due_date:string;assignee_user_id:string|null;status:string;qc_state:string;accepted_at:string|null;started_at:string|null;notes:string|null;};
type PageProps={params:Promise<{id:string}>;searchParams:Promise<{action?:string;error?:string}>};

function day(value:string){return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(`${value}T00:00:00`));}
function qty(value:number){return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));}

export default async function PrintJobDetailPage({params,searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const isProduction=roles.has("PRINTER_PRODUCTION");
  if(!isOwner&&!isProduction) redirect("/");
  const {id}=await params; const state=await searchParams;

  let rows:Job[];
  try{rows=await supabaseRest<Job[]>("rpc/print_job_tracking",{method:"POST",body:JSON.stringify({p_print_job_id:id})});}
  catch(error){if(error instanceof SupabaseRestError&&error.status===401) redirect("/login?error=session"); throw error;}
  const job=rows[0]; if(!job) notFound();

  const actions=job.status==="WAITING"?["ACCEPTED","CANCELLED"]:job.status==="ACCEPTED"?["IN_PROGRESS","CANCELLED"]:job.status==="IN_PROGRESS"?["WAITING_QC","CANCELLED"]:[];

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-040</p><h1>{job.job_number}</h1><p className="muted">{job.order_number} · {job.customer_name} · {job.status}</p></div><div className="hero-actions"><Link href="/print-jobs" className="button button-secondary">Print Jobs</Link><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link></div></header>
    {state.action?<section className="content-card"><p className="permission-note">Print-job action completed: {state.action}.</p></section>:null}
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất thao tác ({state.error}).</p></section>:null}

    <section className="metric-grid"><article className="metric-card"><span>Status</span><strong>{job.status}</strong></article><article className="metric-card"><span>QC</span><strong>{job.qc_state}</strong></article><article className="metric-card"><span>Due</span><strong className="metric-small">{day(job.due_date)}</strong></article><article className="metric-card"><span>Assignment</span><strong className="metric-small">{job.assignee_user_id?"ASSIGNED":"OPS-041"}</strong></article></section>

    <section className="dashboard-grid"><article className="content-card"><h2>Immutable production snapshot</h2><p><strong>SKU:</strong> {job.sku_code} · {job.product_name}</p><p><strong>Product type:</strong> {job.product_type_snapshot??"—"}</p><p><strong>Quantity:</strong> {qty(job.quantity_base_units)}</p><p><strong>Colors:</strong> {job.print_color_count}</p><p><strong>Specification:</strong> {job.print_specification??"—"}</p><p><strong>Artwork:</strong> {job.artwork_reference??"—"}</p><p><strong>Notes:</strong> {job.notes??"—"}</p></article><aside className="content-card"><h2>Execution boundary</h2><p className="muted">OPS-040 cho phép vận hành đến WAITING_QC. Assignment/mobile queue mở ở OPS-041. QC result, evidence và COMPLETED mở ở OPS-042.</p><p><strong>Accepted:</strong> {job.accepted_at?"YES":"NO"}</p><p><strong>Started:</strong> {job.started_at?"YES":"NO"}</p></aside></section>

    {actions.length>0?<section className="content-card"><h2>Production lifecycle</h2><p className="muted">WAITING → ACCEPTED → IN_PROGRESS → WAITING_QC.</p><div className="hero-actions">{actions.map(action=><form action="/api/print-jobs/operations" method="post" key={action}><input type="hidden" name="operation" value="status"/><input type="hidden" name="print_job_id" value={job.print_job_id}/><input type="hidden" name="status" value={action}/><input name="note" placeholder="Transition note"/><button type="submit" className={action==="CANCELLED"?"button button-secondary":"button button-primary"}>{action}</button></form>)}</div></section>:null}
  </main>;
}

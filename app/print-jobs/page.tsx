import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Requirement = { sales_order_item_id:string; order_number:string; customer_name:string; sku_code:string; product_name:string; quantity_base_units:number; print_color_count:number; print_specification:string|null; artwork_reference:string|null; due_date:string; order_print_status:string; };
type Job = { print_job_id:string; job_number:string; order_number:string; customer_name:string; sku_code:string; product_name:string; quantity_base_units:number; print_color_count:number; due_date:string; status:string; qc_state:string; };
type PageProps = { searchParams: Promise<{ error?: string }> };

function day(value:string){return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(\`\${value}T00:00:00\`));}
function qty(value:number){return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));}

export default async function PrintJobsPage({searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const isProduction=roles.has("PRINTER_PRODUCTION");
  const state=await searchParams;
  if(!isOwner&&!isProduction) redirect("/");

  let jobs:Job[]=[]; let requirements:Requirement[]=[];
  try{
    jobs=await supabaseRest<Job[]>("rpc/print_job_tracking",{method:"POST",body:JSON.stringify({p_print_job_id:null})});
    if(isOwner) requirements=await supabaseRest<Requirement[]>("rpc/print_job_requirement_queue",{method:"POST",body:"{}"});
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401) redirect("/login?error=session");
    throw error;
  }

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-040</p><h1>Print Jobs</h1><p className="muted">Materialize PRINTED requirements và vận hành đến WAITING_QC. Assignment/QC completion thuộc OPS-041/042.</p></div><div className="hero-actions"><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link><Link href="/" className="button button-secondary">Trang chủ</Link></div></header>
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất print-job action ({state.error}).</p></section>:null}

    <section className="content-card"><h2>Production tracking</h2><div className="table-wrap"><table><thead><tr><th>Job</th><th>Order / Customer</th><th>SKU</th><th>Qty / Colors</th><th>Due</th><th>Status</th></tr></thead><tbody>
      {jobs.map(job=><tr key={job.print_job_id}><td><Link href={\`/print-jobs/\${job.print_job_id}\`}><strong>{job.job_number}</strong></Link></td><td>{job.order_number}<div className="subtle">{job.customer_name}</div></td><td>{job.sku_code}<div className="subtle">{job.product_name}</div></td><td>{qty(job.quantity_base_units)}<div className="subtle">{job.print_color_count} color(s)</div></td><td>{day(job.due_date)}</td><td><strong>{job.status}</strong><div className="subtle">QC {job.qc_state}</div></td></tr>)}
      {jobs.length===0?<tr><td colSpan={6} className="empty-state">{isProduction?"Chưa có job được assignment cho tài khoản này.":"Chưa có print job."}</td></tr>:null}
    </tbody></table></div></section>

    {isOwner?<section className="content-card"><h2>PRINTED requirements chưa có active job</h2><p className="muted">Mỗi PRINTED sales-order line có tối đa một active job.</p><div className="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>SKU / Product</th><th>Production spec</th><th>Due</th><th>Materialize</th></tr></thead><tbody>
      {requirements.map(req=><tr key={req.sales_order_item_id}><td><strong>{req.order_number}</strong><div className="subtle">{req.order_print_status}</div></td><td>{req.customer_name}</td><td>{req.sku_code}<div className="subtle">{req.product_name} · {qty(req.quantity_base_units)}</div></td><td>{req.print_color_count} color(s)<div className="subtle">{req.print_specification??"—"} · artwork {req.artwork_reference??"—"}</div></td><td>{day(req.due_date)}</td><td><form action="/api/print-jobs/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="create"/><input type="hidden" name="sales_order_item_id" value={req.sales_order_item_id}/><input name="job_number" required placeholder="PJ-2026-0001"/><input name="notes" placeholder="Notes"/><button type="submit" className="button button-primary">Create job</button></form></td></tr>)}
      {requirements.length===0?<tr><td colSpan={6} className="empty-state">Không còn PRINTED requirement cần materialize.</td></tr>:null}
    </tbody></table></div></section>:null}
  </main>;
}

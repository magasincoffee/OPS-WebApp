import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type MobileJob={
  print_job_id:string;
  job_number:string;
  order_number:string;
  customer_name:string;
  sku_code:string;
  product_name:string;
  product_type_snapshot:string|null;
  quantity_base_units:number;
  print_color_count:number;
  print_specification:string|null;
  artwork_reference:string|null;
  due_date:string;
  status:string;
  qc_state:string;
  accepted_at:string|null;
  started_at:string|null;
  notes:string|null;
};

function day(value:string){
  return new Intl.DateTimeFormat("vi-VN",{dateStyle:"medium"}).format(new Date(value+"T00:00:00"));
}
function qty(value:number){
  return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));
}

export default async function ProductionMobileQueuePage(){
  const roles=await getCurrentRoles();
  if(!roles.has("PRINTER_PRODUCTION")) redirect("/");

  let jobs:MobileJob[];
  try{
    jobs=await supabaseRest<MobileJob[]>("rpc/production_mobile_work_queue",{method:"POST",body:"{}"});
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401) redirect("/login?error=session");
    throw error;
  }

  return <main className="app-shell">
    <header className="topbar">
      <div><p className="eyebrow">OPS-WEBAPP · OPS-041 · MOBILE</p><h1>My Production Queue</h1><p className="muted">Chỉ hiển thị print jobs được assign cho tài khoản hiện tại. Không có giá bán, cost, margin hoặc công nợ.</p></div>
      <div className="hero-actions"><Link href="/print-jobs" className="button button-secondary">Print Jobs</Link><Link href="/" className="button button-secondary">Trang chủ</Link></div>
    </header>

    {jobs.length===0?<section className="content-card"><p className="empty-state">Hiện không có print job được assign.</p></section>:null}

    <section className="dashboard-grid">
      {jobs.map(job=>{
        const nextStatus=job.status==="WAITING"?"ACCEPTED":job.status==="ACCEPTED"?"IN_PROGRESS":job.status==="IN_PROGRESS"?"WAITING_QC":null;
        return <article className="content-card" key={job.print_job_id}>
          <div className="section-heading"><div><p className="eyebrow">{job.status}</p><h2>{job.job_number}</h2><p className="muted">Due {day(job.due_date)}</p></div><Link href={"/print-jobs/"+job.print_job_id} className="button button-secondary">Chi tiết</Link></div>
          <p><strong>Order:</strong> {job.order_number}</p>
          <p><strong>Customer:</strong> {job.customer_name}</p>
          <p><strong>SKU:</strong> {job.sku_code} · {job.product_name}</p>
          <p><strong>Quantity:</strong> {qty(job.quantity_base_units)}</p>
          <p><strong>Colors:</strong> {job.print_color_count}</p>
          <p><strong>Specification:</strong> {job.print_specification??"—"}</p>
          <p><strong>Artwork:</strong> {job.artwork_reference??"—"}</p>
          {job.notes?<p><strong>Notes:</strong> {job.notes}</p>:null}
          {nextStatus?<form action="/api/print-jobs/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="status"/><input type="hidden" name="print_job_id" value={job.print_job_id}/><input type="hidden" name="status" value={nextStatus}/><input name="note" placeholder="Work note"/><button type="submit" className="button button-primary">{nextStatus==="ACCEPTED"?"Accept job":nextStatus==="IN_PROGRESS"?"Start production":"Send to QC"}</button></form>:<p className="permission-note">Đang chờ QC — completion thuộc OPS-042.</p>}
        </article>;
      })}
    </section>
  </main>;
}

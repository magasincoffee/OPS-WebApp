import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Tracking={
  delivery_id:string;delivery_number:string;sales_order_id:string;order_number:string;customer_name:string;
  status:string;consignee_name:string;parcel_info:string|null;carrier_note:string|null;delivery_reference:string|null;
  ready_at:string|null;dispatch_date:string|null;completed_at:string|null;
};
type Queue={sales_order_id:string;order_number:string;customer_name:string;requested_due_date:string|null;warehouse_status:string;print_status:string;ready_eligible:boolean;line_count:number};
type PageProps={searchParams:Promise<{error?:string}>};

function date(value:string|null){
  if(!value)return "—";
  return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(`${value}T00:00:00`));
}

export default async function DeliveriesPage({searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const canManage=roles.has("OWNER_ADMIN")||roles.has("WAREHOUSE");
  const canView=canManage||roles.has("SALES");
  const state=await searchParams;
  if(!canView) redirect("/");

  let tracking:Tracking[],queue:Queue[];
  try{
    [tracking,queue]=await Promise.all([
      supabaseRest<Tracking[]>("rpc/delivery_tracking",{method:"POST",body:JSON.stringify({p_delivery_id:null})}),
      supabaseRest<Queue[]>("rpc/delivery_work_queue",{method:"POST",body:"{}"}),
    ]);
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");
    throw error;
  }

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-033</p><h1>Deliveries</h1><p className="muted">Ready-to-ship, parcel/carrier details, dispatch và completion.</p></div><div className="hero-actions"><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link><Link href="/" className="button button-secondary">Trang chủ</Link></div></header>
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất delivery action ({state.error}).</p></section>:null}

    <section className="content-card"><h2>Delivery tracking</h2><div className="table-wrap"><table><thead><tr><th>Delivery</th><th>Order</th><th>Customer / consignee</th><th>Status</th><th>Parcel / carrier</th><th>Dispatch</th></tr></thead><tbody>
      {tracking.map(row=><tr key={row.delivery_id}><td><Link href={`/deliveries/${row.delivery_id}`}><strong>{row.delivery_number}</strong></Link></td><td>{row.order_number}</td><td>{row.customer_name}<div className="subtle">{row.consignee_name}</div></td><td><strong>{row.status}</strong></td><td>{row.parcel_info??"—"}<div className="subtle">{row.carrier_note??row.delivery_reference??"—"}</div></td><td>{date(row.dispatch_date)}</td></tr>)}
      {tracking.length===0?<tr><td colSpan={6} className="empty-state">Chưa có delivery.</td></tr>:null}
    </tbody></table></div></section>

    {canManage?<section className="dashboard-grid">
      <article className="content-card"><h2>Orders chưa có active delivery</h2><div className="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>WH</th><th>Print</th><th>Due</th></tr></thead><tbody>{queue.map(row=><tr key={row.sales_order_id}><td><strong>{row.order_number}</strong><div className="subtle">{row.line_count} line(s)</div></td><td>{row.customer_name}</td><td>{row.warehouse_status}</td><td>{row.print_status}</td><td>{date(row.requested_due_date)}</td></tr>)}{queue.length===0?<tr><td colSpan={5} className="empty-state">Không có order chờ tạo delivery.</td></tr>:null}</tbody></table></div></article>
      <aside className="content-card"><h2>Tạo delivery</h2><p className="muted">Có thể tạo trước; READY_TO_SHIP chỉ mở khi warehouse=ISSUED và print đã sẵn sàng.</p><form action="/api/deliveries/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="create"/><label>Sales order *<select name="sales_order_id" required defaultValue=""><option value="" disabled>Chọn order</option>{queue.map(row=><option key={row.sales_order_id} value={row.sales_order_id}>{row.order_number} · {row.customer_name}</option>)}</select></label><label>Delivery number *<input name="delivery_number" required placeholder="DLV-2026-0001"/></label><label>Consignee *<input name="consignee_name" required/></label><div className="form-row"><label>Phone<input name="consignee_phone"/></label><label>Address<input name="consignee_address"/></label></div><label>Parcel/package info<textarea name="parcel_info" rows={2} placeholder="Ví dụ: 3 cartons, 1 pallet"/></label><div className="form-row"><label>Carrier / chành xe note<input name="carrier_note"/></label><label>Delivery reference<input name="delivery_reference"/></label></div><label>Notes<textarea name="notes" rows={2}/></label><button type="submit" className="button button-primary">Tạo NOT_READY delivery</button></form></aside>
    </section>:null}
  </main>;
}

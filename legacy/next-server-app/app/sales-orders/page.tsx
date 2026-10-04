import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Customer={id:string;display_name:string;customer_code:string|null;is_active:boolean};
type Order={id:string;order_number:string;customer_id:string;order_status:string;print_status:string;warehouse_status:string;payment_status:string;delivery_status:string;order_date:string;requested_due_date:string|null;currency_code:string;updated_at:string};
type Total={sales_order_id:string;total_amount:number;currency_code:string};
type Quotation={id:string;quotation_number:string;customer_id:string;status:string;currency_code:string};
type PageProps={searchParams:Promise<{error?:string}>};

function money(value:number,currency:string){return new Intl.NumberFormat("vi-VN",{style:"currency",currency,maximumFractionDigits:currency==="VND"?0:2}).format(Number(value));}
function date(value:string|null){if(!value)return "—";return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(`${value}T00:00:00`));}

export default async function SalesOrdersPage({searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const canManage=roles.has("OWNER_ADMIN")||roles.has("SALES");
  const canView=canManage||roles.has("ACCOUNTING");
  const state=await searchParams;
  if(!canView){
    return <main className="app-shell"><header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-031</p><h1>Sales Orders</h1></div><Link href="/" className="button button-secondary">Trang chủ</Link></header><section className="content-card"><p className="permission-note">Không có quyền xem sales orders.</p></section></main>;
  }

  let orders:Order[],customers:Customer[],totals:Total[],accepted:Quotation[];
  try{
    [orders,customers,totals,accepted]=await Promise.all([
      supabaseRest<Order[]>("sales_orders?select=id,order_number,customer_id,order_status,print_status,warehouse_status,payment_status,delivery_status,order_date,requested_due_date,currency_code,updated_at&order=updated_at.desc&limit=500"),
      supabaseRest<Customer[]>("customers?select=id,display_name,customer_code,is_active&is_active=eq.true&order=display_name.asc&limit=2000"),
      supabaseRest<Total[]>("sales_order_totals?select=sales_order_id,total_amount,currency_code&limit=500"),
      supabaseRest<Quotation[]>("quotations?status=eq.ACCEPTED&select=id,quotation_number,customer_id,status,currency_code&order=updated_at.desc&limit=500"),
    ]);
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");
    throw error;
  }
  const customerById=new Map(customers.map(row=>[row.id,row]));
  const totalById=new Map(totals.map(row=>[row.sales_order_id,row]));

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-031</p><h1>Sales Orders</h1><p className="muted">Order lifecycle độc lập với print, warehouse, payment và delivery.</p></div><div className="hero-actions"><Link href="/quotations" className="button button-secondary">Quotations</Link><Link href="/inventory" className="button button-secondary">Inventory</Link><Link href="/" className="button button-secondary">Trang chủ</Link></div></header>
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất sales-order action ({state.error}).</p></section>:null}

    <section className="content-card"><h2>Danh sách orders</h2><div className="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>Date</th><th>Due</th><th>Status dimensions</th><th>Total</th></tr></thead><tbody>
      {orders.map(order=>{const total=totalById.get(order.id);return <tr key={order.id}><td><Link href={`/sales-orders/${order.id}`}><strong>{order.order_number}</strong></Link></td><td>{customerById.get(order.customer_id)?.display_name??"—"}</td><td>{date(order.order_date)}</td><td>{date(order.requested_due_date)}</td><td><strong>{order.order_status}</strong><div className="subtle">Print {order.print_status} · WH {order.warehouse_status}</div><div className="subtle">Payment {order.payment_status} · Delivery {order.delivery_status}</div></td><td>{money(total?.total_amount??0,total?.currency_code??order.currency_code)}</td></tr>;})}
      {orders.length===0?<tr><td colSpan={6} className="empty-state">Chưa có sales order.</td></tr>:null}
    </tbody></table></div></section>

    {canManage?<section className="dashboard-grid">
      <article className="content-card"><h2>Convert ACCEPTED quotation</h2><form action="/api/sales-orders/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="convert_quotation"/><label>Quotation *<select name="quotation_id" required defaultValue=""><option value="" disabled>Chọn ACCEPTED quotation</option>{accepted.map(q=><option key={q.id} value={q.id}>{q.quotation_number} · {customerById.get(q.customer_id)?.display_name??"Customer"}</option>)}</select></label><label>Sales order number *<input name="order_number" required placeholder="SO-2026-0001"/></label><div className="form-row"><label>Requested due date<input type="date" name="requested_due_date"/></label><label>Notes<input name="notes"/></label></div><button type="submit" className="button button-primary">Convert sang DRAFT order</button></form></article>
      <aside className="content-card"><h2>Tạo direct DRAFT order</h2><form action="/api/sales-orders/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="create"/><label>Order number *<input name="order_number" required placeholder="SO-2026-0002"/></label><label>Khách hàng *<select name="customer_id" required defaultValue=""><option value="" disabled>Chọn khách hàng</option>{customers.map(c=><option key={c.id} value={c.id}>{c.customer_code?`${c.customer_code} · `:""}{c.display_name}</option>)}</select></label><div className="form-row"><label>Requested due date<input type="date" name="requested_due_date"/></label><label>Currency<input name="currency_code" defaultValue="VND" pattern="[A-Za-z]{3}" required/></label></div><label>Notes<textarea name="notes" rows={3}/></label><button type="submit" className="button button-primary">Tạo direct order</button></form></aside>
    </section>:null}
  </main>;
}

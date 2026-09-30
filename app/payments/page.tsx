import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Followup={sales_order_id:string;order_number:string;customer_id:string;customer_name:string;order_total_amount:number;valid_payment_amount:number;receivable_amount:number;currency_code:string;payment_status:string;order_status:string;};
type Payment={id:string;customer_id:string;sales_order_id:string|null;amount:number;payment_date:string;payment_method:string;status:string;reference:string|null;note:string|null;created_at:string;};
type Evidence={id:string;linked_entity_id:string;original_file_name:string;created_at:string;};

function money(value:number,currency:string){return new Intl.NumberFormat("vi-VN",{style:"currency",currency,maximumFractionDigits:currency==="VND"?0:2}).format(Number(value));}
function day(value:string){return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(value+"T00:00:00"));}

export default async function PaymentsPage(){
  const roles=await getCurrentRoles();
  if(!roles.has("OWNER_ADMIN")&&!roles.has("ACCOUNTING")) redirect("/");
  let orders:Followup[]=[]; let payments:Payment[]=[]; let evidence:Evidence[]=[];
  try{
    [orders,payments,evidence]=await Promise.all([
      supabaseRest<Followup[]>("sales_receivable_followup?order_status=eq.CONFIRMED&select=sales_order_id,order_number,customer_id,customer_name,order_total_amount,valid_payment_amount,receivable_amount,currency_code,payment_status,order_status&order=order_date.desc&limit=500"),
      supabaseRest<Payment[]>("customer_payments?select=id,customer_id,sales_order_id,amount,payment_date,payment_method,status,reference,note,created_at&order=payment_date.desc,created_at.desc&limit=500"),
      supabaseRest<Evidence[]>("attachments?linked_entity_type=eq.CUSTOMER_PAYMENT&attachment_kind=eq.PAYMENT_EVIDENCE&select=id,linked_entity_id,original_file_name,created_at&order=created_at.desc&limit=1000"),
    ]);
  }catch(error){if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");throw error;}
  const orderById=new Map(orders.map(o=>[o.sales_order_id,o]));
  const evidenceByPayment=new Map<string,Evidence[]>(); for(const item of evidence){const g=evidenceByPayment.get(item.linked_entity_id)??[];g.push(item);evidenceByPayment.set(item.linked_entity_id,g);}
  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-050</p><h1>Customer Payments</h1><p className="muted">Finance-only payment recording. Ledger/receivable posting remains OPS-051.</p></div><div className="hero-actions"><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link><Link href="/" className="button button-secondary">Trang chủ</Link></div></header>

    <section className="content-card"><h2>Record order payment</h2><form action="/api/payments/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="record"/><label>Confirmed order *<select name="sales_order_id" required defaultValue=""><option value="" disabled>Chọn order</option>{orders.filter(o=>Number(o.receivable_amount)>0).map(o=><option key={o.sales_order_id} value={o.sales_order_id}>{o.order_number} · {o.customer_name} · outstanding {money(o.receivable_amount,o.currency_code)}</option>)}</select></label><div className="form-row"><label>Amount *<input type="number" name="amount" min="0.000001" step="any" required/></label><label>Payment date *<input type="date" name="payment_date" required defaultValue={new Date().toISOString().slice(0,10)}/></label></div><div className="form-row"><label>Method *<input name="payment_method" required placeholder="BANK_TRANSFER / CASH"/></label><label>Reference<input name="reference"/></label></div><label>Note<textarea name="note" rows={2}/></label><button type="submit" className="button button-primary">Record payment</button></form></section>

    <section className="content-card"><h2>Confirmed orders / outstanding</h2><div className="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>Total</th><th>Paid</th><th>Outstanding</th><th>Status</th></tr></thead><tbody>{orders.map(o=><tr key={o.sales_order_id}><td><Link href={"/sales-orders/"+o.sales_order_id}>{o.order_number}</Link></td><td>{o.customer_name}</td><td>{money(o.order_total_amount,o.currency_code)}</td><td>{money(o.valid_payment_amount,o.currency_code)}</td><td>{money(o.receivable_amount,o.currency_code)}</td><td>{o.payment_status}</td></tr>)}{orders.length===0?<tr><td colSpan={6} className="empty-state">Không có confirmed order.</td></tr>:null}</tbody></table></div></section>

    <section className="content-card"><h2>Payment history</h2><div className="table-wrap"><table><thead><tr><th>Date / Reference</th><th>Order</th><th>Amount</th><th>Method</th><th>Status</th><th>Evidence</th><th></th></tr></thead><tbody>{payments.map(p=>{const order=p.sales_order_id?orderById.get(p.sales_order_id):undefined;const files=evidenceByPayment.get(p.id)??[];return <tr key={p.id}><td>{day(p.payment_date)}<div className="subtle">{p.reference??"—"}</div></td><td>{order?.order_number??p.sales_order_id??"—"}</td><td>{order?money(p.amount,order.currency_code):String(p.amount)}</td><td>{p.payment_method}</td><td>{p.status}</td><td>{files.map(file=><div key={file.id}><Link href={"/api/payments/evidence/"+file.id}>{file.original_file_name}</Link></div>)}{p.status==="POSTED"?<form action={"/api/payments/"+p.id+"/evidence"} method="post" encType="multipart/form-data" className="form-stack"><input type="file" name="file" required/><button type="submit" className="button button-secondary">Upload evidence</button></form>:null}</td><td>{p.status==="POSTED"?<form action="/api/payments/operations" method="post"><input type="hidden" name="operation" value="void"/><input type="hidden" name="customer_payment_id" value={p.id}/><button type="submit" className="button button-secondary">Void</button></form>:null}</td></tr>;})}{payments.length===0?<tr><td colSpan={7} className="empty-state">Chưa có payment.</td></tr>:null}</tbody></table></div></section>
  </main>;
}

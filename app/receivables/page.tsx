import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Followup={sales_order_id:string;order_number:string;customer_id:string;customer_name:string;order_total_amount:number;valid_payment_amount:number;receivable_amount:number;currency_code:string;payment_status:string;order_status:string;order_date:string;requested_due_date:string|null;};
type Balance={customer_id:string;customer_name:string;currency_code:string;balance_amount:number;};
type Ledger={entry_id:string;customer_id:string;customer_name:string;entry_type:string;amount:number;effective_amount:number;currency_code:string|null;occurred_at:string;created_by_user_id:string|null;sales_order_id:string|null;order_number:string|null;customer_payment_id:string|null;payment_reference:string|null;payment_status:string|null;note:string|null;};

function money(value:number,currency:string){return new Intl.NumberFormat("vi-VN",{style:"currency",currency,maximumFractionDigits:currency==="VND"?0:2}).format(Number(value));}
function date(value:string|null){if(!value)return "—";return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(value));}

export default async function ReceivablesPage(){
  const roles=await getCurrentRoles();
  const finance=roles.has("OWNER_ADMIN")||roles.has("ACCOUNTING");
  const sales=roles.has("SALES");
  if(!finance&&!sales)redirect("/");

  let followup:Followup[]=[]; let balances:Balance[]=[]; let ledger:Ledger[]=[];
  try{
    followup=await supabaseRest<Followup[]>("sales_receivable_followup?select=sales_order_id,order_number,customer_id,customer_name,order_total_amount,valid_payment_amount,receivable_amount,currency_code,payment_status,order_status,order_date,requested_due_date&order=order_date.desc&limit=1000");
    if(finance){
      [balances,ledger]=await Promise.all([
        supabaseRest<Balance[]>("customer_ledger_balances_by_currency?select=customer_id,customer_name,currency_code,balance_amount&order=customer_name.asc,currency_code.asc&limit=2000"),
        supabaseRest<Ledger[]>("customer_ledger_history?select=entry_id,customer_id,customer_name,entry_type,amount,effective_amount,currency_code,occurred_at,created_by_user_id,sales_order_id,order_number,customer_payment_id,payment_reference,payment_status,note&order=occurred_at.desc&limit=1000"),
      ]);
    }
  }catch(error){if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");throw error;}

  const outstanding=followup.filter(row=>Number(row.receivable_amount)>0);
  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-051</p><h1>Customer Receivables</h1><p className="muted">Source-backed order debits and payment credits. Balances are kept per currency.</p></div><div className="hero-actions">{finance?<Link href="/payments" className="button button-primary">Payments</Link>:null}<Link href="/customers" className="button button-secondary">Customers</Link><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link><Link href="/" className="button button-secondary">Trang chủ</Link></div></header>

    <section className="content-card"><div className="section-heading"><div><h2>Outstanding orders</h2><p className="muted">SALES sees this sanitized follow-up view; direct payment and ledger rows remain finance-only.</p></div><strong>{outstanding.length} order(s)</strong></div><div className="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>Total</th><th>Valid payments</th><th>Receivable</th><th>Status</th><th>Due</th></tr></thead><tbody>{outstanding.map(row=><tr key={row.sales_order_id}><td><Link href={"/sales-orders/"+row.sales_order_id}>{row.order_number}</Link></td><td><Link href={"/customers/"+row.customer_id}>{row.customer_name}</Link></td><td>{money(row.order_total_amount,row.currency_code)}</td><td>{money(row.valid_payment_amount,row.currency_code)}</td><td><strong>{money(row.receivable_amount,row.currency_code)}</strong></td><td>{row.payment_status}</td><td>{date(row.requested_due_date)}</td></tr>)}{outstanding.length===0?<tr><td colSpan={7} className="empty-state">Không có khoản phải thu đang mở.</td></tr>:null}</tbody></table></div></section>

    {finance?<><section className="content-card"><h2>Customer balance by currency</h2><p className="muted">Không cộng chéo các currency. Debit của order CANCELLED và credit của payment VOIDED có hiệu lực bằng 0 nhưng vẫn còn trong lịch sử.</p><div className="table-wrap"><table><thead><tr><th>Customer</th><th>Currency</th><th>Current balance</th></tr></thead><tbody>{balances.map(row=><tr key={row.customer_id+"-"+row.currency_code}><td><Link href={"/customers/"+row.customer_id}>{row.customer_name}</Link></td><td>{row.currency_code}</td><td><strong>{money(row.balance_amount,row.currency_code)}</strong></td></tr>)}{balances.length===0?<tr><td colSpan={3} className="empty-state">Chưa có ledger balance.</td></tr>:null}</tbody></table></div></section>

    <section className="content-card"><h2>Ledger history</h2><div className="table-wrap"><table><thead><tr><th>Date</th><th>Customer</th><th>Source</th><th>Entry</th><th>Amount</th><th>Effective</th><th>Status / Note</th></tr></thead><tbody>{ledger.map(row=><tr key={row.entry_id}><td>{date(row.occurred_at)}</td><td>{row.customer_name}</td><td>{row.order_number??row.payment_reference??row.customer_payment_id??"—"}</td><td>{row.entry_type}</td><td>{row.currency_code?money(row.amount,row.currency_code):String(row.amount)}</td><td>{row.currency_code?money(row.effective_amount,row.currency_code):String(row.effective_amount)}</td><td>{row.payment_status??"ACTIVE"}<div className="subtle">{row.note??"—"}</div></td></tr>)}{ledger.length===0?<tr><td colSpan={7} className="empty-state">Chưa có ledger entry.</td></tr>:null}</tbody></table></div></section></>:null}
  </main>;
}

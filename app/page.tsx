import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { getAccessToken, SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Customer={id:string;is_active:boolean};
type Quotation={id:string;status:string};
type SalesOrder={id:string;order_status:string;delivery_status:string;payment_status:string};
type Receivable={sales_order_id:string;receivable_amount:number;currency_code:string;payment_status:string};
type Payment={id:string;status:string};
type Balance={customer_id:string;currency_code:string;balance_amount:number};
type Receipt={id:string};
type LowStock={product_variant_id:string};
type Reservation={sales_order_item_id:string};
type DeliveryQueue={sales_order_id:string};
type PrintJob={print_job_id:string;status:string;qc_state:string};
type ProductionJob={print_job_id:string;status:string;qc_state:string};

function countOpenOrders(rows:SalesOrder[]){
  return rows.filter(row=>!["COMPLETED","CANCELLED"].includes(row.order_status)).length;
}
function countOutstanding(rows:Receivable[]){
  return rows.filter(row=>Number(row.receivable_amount)>0).length;
}
function navLink(href:string,label:string,primary=false){
  return <Link href={href} className={primary?"button button-primary":"button button-secondary"}>{label}</Link>;
}

export default async function HomePage(){
  const accessToken=await getAccessToken();
  if(!accessToken)redirect("/login");

  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const isSales=roles.has("SALES");
  const isAccounting=roles.has("ACCOUNTING");
  const isWarehouse=roles.has("WAREHOUSE");
  const isProduction=roles.has("PRINTER_PRODUCTION");

  const canSales=isOwner||isSales;
  const canFinance=isOwner||isAccounting;
  const canWarehouse=isOwner||isWarehouse;
  const canReceivables=isOwner||isSales||isAccounting;

  let customers:Customer[]=[];
  let quotations:Quotation[]=[];
  let orders:SalesOrder[]=[];
  let receivables:Receivable[]=[];
  let payments:Payment[]=[];
  let balances:Balance[]=[];
  let receipts:Receipt[]=[];
  let lowStock:LowStock[]=[];
  let reservations:Reservation[]=[];
  let deliveryQueue:DeliveryQueue[]=[];
  let ownerPrintJobs:PrintJob[]=[];
  let myProductionJobs:ProductionJob[]=[];

  try{
    const requests:Promise<void>[]=[];

    if(canSales){
      requests.push((async()=>{
        [customers,quotations,orders]=await Promise.all([
          supabaseRest<Customer[]>("customers?select=id,is_active&limit=5000"),
          supabaseRest<Quotation[]>("quotations?select=id,status&limit=5000"),
          supabaseRest<SalesOrder[]>("sales_orders?select=id,order_status,delivery_status,payment_status&limit=5000"),
        ]);
      })());
    }else if(isAccounting){
      requests.push((async()=>{
        orders=await supabaseRest<SalesOrder[]>("sales_orders?select=id,order_status,delivery_status,payment_status&limit=5000");
      })());
    }

    if(canReceivables){
      requests.push((async()=>{
        receivables=await supabaseRest<Receivable[]>("sales_receivable_followup?select=sales_order_id,receivable_amount,currency_code,payment_status&limit=5000");
      })());
    }

    if(canFinance){
      requests.push((async()=>{
        [payments,balances]=await Promise.all([
          supabaseRest<Payment[]>("customer_payments?select=id,status&limit=5000"),
          supabaseRest<Balance[]>("customer_ledger_balances_by_currency?select=customer_id,currency_code,balance_amount&limit=5000"),
        ]);
      })());
    }

    if(canWarehouse){
      requests.push((async()=>{
        [receipts,lowStock,reservations,deliveryQueue]=await Promise.all([
          supabaseRest<Receipt[]>("goods_receipts?select=id&limit=5000"),
          supabaseRest<LowStock[]>("inventory_low_stock?select=product_variant_id&limit=5000"),
          supabaseRest<Reservation[]>("rpc/inventory_reservation_work_queue",{method:"POST",body:"{}"}),
          supabaseRest<DeliveryQueue[]>("rpc/delivery_work_queue",{method:"POST",body:"{}"}),
        ]);
      })());
    }

    if(isOwner){
      requests.push((async()=>{
        ownerPrintJobs=await supabaseRest<PrintJob[]>("rpc/print_job_tracking",{method:"POST",body:JSON.stringify({p_print_job_id:null})});
      })());
    }

    if(isProduction){
      requests.push((async()=>{
        myProductionJobs=await supabaseRest<ProductionJob[]>("rpc/production_mobile_work_queue",{method:"POST",body:"{}"});
      })());
    }

    await Promise.all(requests);
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");
    throw error;
  }

  const activeCustomers=customers.filter(row=>row.is_active).length;
  const openQuotes=quotations.filter(row=>!["ACCEPTED","REJECTED","EXPIRED"].includes(row.status)).length;
  const openOrders=countOpenOrders(orders);
  const outstandingOrders=countOutstanding(receivables);
  const postedPayments=payments.filter(row=>row.status==="POSTED").length;
  const positiveBalances=balances.filter(row=>Number(row.balance_amount)>0).length;
  const activePrintJobs=ownerPrintJobs.filter(row=>!["COMPLETED","CANCELLED"].includes(row.status)).length;
  const waitingQc=ownerPrintJobs.filter(row=>row.status==="WAITING_QC").length;
  const myWaitingQc=myProductionJobs.filter(row=>row.status==="WAITING_QC").length;
  const roleLabels=[
    isOwner?"OWNER / ADMIN":null,
    isSales?"SALES":null,
    isAccounting?"ACCOUNTING":null,
    isWarehouse?"WAREHOUSE":null,
    isProduction?"PRINTER / PRODUCTION":null,
  ].filter(Boolean).join(" · ");

  return <main className="app-shell">
    <header className="topbar">
      <div>
        <p className="eyebrow">OPS-WEBAPP · OPS-060</p>
        <h1>Operations Dashboard</h1>
        <p className="muted">{roleLabels||"Chưa được gán vai trò"}</p>
      </div>
      <form action="/api/auth/logout" method="post">
        <button type="submit" className="button button-secondary">Đăng xuất</button>
      </form>
    </header>

    {roles.size===0?<section className="content-card"><p className="permission-note">Tài khoản đã đăng nhập nhưng chưa được gán vai trò vận hành. Liên hệ OWNER/ADMIN để được cấp quyền.</p></section>:null}

    {canSales?<section className="content-card">
      <div className="section-heading"><div><p className="eyebrow">SALES</p><h2>Customer & sales flow</h2><p className="muted">Customer, quotation, order, delivery tracking và receivable follow-up theo quyền SALES.</p></div></div>
      <div className="metric-grid">
        <article className="metric-card"><span>Active customers</span><strong>{activeCustomers}</strong></article>
        <article className="metric-card"><span>Open quotations</span><strong>{openQuotes}</strong></article>
        <article className="metric-card"><span>Open sales orders</span><strong>{openOrders}</strong></article>
        <article className="metric-card"><span>Outstanding orders</span><strong>{outstandingOrders}</strong></article>
      </div>
      <div className="hero-actions">{navLink("/customers","Khách hàng",true)}{navLink("/quotations","Quotations")}{navLink("/sales-orders","Sales Orders")}{navLink("/deliveries","Deliveries")}{navLink("/receivables","Receivables")}</div>
    </section>:null}

    {canFinance?<section className="content-card">
      <div className="section-heading"><div><p className="eyebrow">ACCOUNTING</p><h2>Finance & receivables</h2><p className="muted">Payment, receivable, order financial state và cost/pricing surfaces. Currency balances remain separated.</p></div></div>
      <div className="metric-grid">
        <article className="metric-card"><span>Posted payments</span><strong>{postedPayments}</strong></article>
        <article className="metric-card"><span>Outstanding orders</span><strong>{outstandingOrders}</strong></article>
        <article className="metric-card"><span>Positive customer/currency balances</span><strong>{positiveBalances}</strong></article>
        <article className="metric-card"><span>Open orders</span><strong>{openOrders}</strong></article>
      </div>
      <div className="hero-actions">{navLink("/payments","Customer Payments",true)}{navLink("/receivables","Receivables")}{navLink("/sales-orders","Sales Orders")}{navLink("/costing","Costing & Pricing")}{navLink("/receipts","Goods Receipts")}</div>
    </section>:null}

    {canWarehouse?<section className="content-card">
      <div className="section-heading"><div><p className="eyebrow">WAREHOUSE</p><h2>Warehouse operations</h2><p className="muted">Goods receipt, stock, reservation/issue workload, low-stock và delivery readiness; không hiển thị profitability.</p></div></div>
      <div className="metric-grid">
        <article className="metric-card"><span>Goods receipts</span><strong>{receipts.length}</strong></article>
        <article className="metric-card"><span>Reservation / issue lines</span><strong>{reservations.length}</strong></article>
        <article className="metric-card"><span>Low-stock SKUs</span><strong>{lowStock.length}</strong></article>
        <article className="metric-card"><span>Orders awaiting delivery setup</span><strong>{deliveryQueue.length}</strong></article>
      </div>
      <div className="hero-actions">{navLink("/inventory","Inventory",true)}{navLink("/receipts","Goods Receipts")}{navLink("/deliveries","Deliveries")}</div>
    </section>:null}

    {isOwner?<section className="content-card">
      <div className="section-heading"><div><p className="eyebrow">OWNER / ADMIN</p><h2>System overview</h2><p className="muted">Cross-functional owner view over current V1 modules. Operational tasks and formal reports remain OPS-061/062.</p></div></div>
      <div className="metric-grid">
        <article className="metric-card"><span>Active print jobs</span><strong>{activePrintJobs}</strong></article>
        <article className="metric-card"><span>Waiting QC</span><strong>{waitingQc}</strong></article>
        <article className="metric-card"><span>Low-stock SKUs</span><strong>{lowStock.length}</strong></article>
        <article className="metric-card"><span>Outstanding orders</span><strong>{outstandingOrders}</strong></article>
      </div>
      <div className="hero-actions">{navLink("/suppliers","Suppliers")}{navLink("/products","Products & SKU")}{navLink("/purchases","Purchase Orders")}{navLink("/print-jobs","Print Jobs",true)}</div>
    </section>:null}

    {isProduction?<section className="content-card">
      <div className="section-heading"><div><p className="eyebrow">PRINTER / PRODUCTION</p><h2>My production workload</h2><p className="muted">Chỉ assigned print jobs của tài khoản hiện tại. Không query hoặc hiển thị cost, margin, debt hay accounting data.</p></div></div>
      <div className="metric-grid">
        <article className="metric-card"><span>Assigned active jobs</span><strong>{myProductionJobs.length}</strong></article>
        <article className="metric-card"><span>Waiting QC</span><strong>{myWaitingQc}</strong></article>
      </div>
      <div className="hero-actions">{navLink("/production","My Production Queue",true)}{navLink("/print-jobs","Print Jobs")}</div>
    </section>:null}
  </main>;
}

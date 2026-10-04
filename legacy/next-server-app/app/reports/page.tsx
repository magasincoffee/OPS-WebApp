import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type PageProps={searchParams:Promise<{from?:string;to?:string}>};
type SalesOrder={id:string;order_number:string;customer_id:string;order_status:string;order_date:string;currency_code:string};
type SalesItem={id:string;sales_order_id:string;product_variant_id:string;base_quantity:number;line_total:number;print_mode:string};
type Customer={id:string;display_name:string};
type Variant={id:string;product_id:string;sku_code:string;minimum_stock_quantity:number;base_inventory_unit:string};
type Product={id:string;name:string};
type Cost={product_variant_id:string;effective_at:string;inventory_cost_basis_per_base_unit:number|null;currency_code:string};
type Receivable={sales_order_id:string;order_number:string;customer_name:string;order_total_amount:number;valid_payment_amount:number;receivable_amount:number;currency_code:string;payment_status:string;order_date:string};
type Payment={id:string;sales_order_id:string|null;amount:number;payment_date:string;payment_method:string;status:string;reference:string|null};
type PaymentOrder={id:string;currency_code:string};
type Movement={id:string;product_variant_id:string;movement_type:string;quantity_delta_base_units:number;reference:string|null;reason:string|null;occurred_at:string};
type Purchase={id:string;po_number:string;supplier_id:string;status:string;order_date:string;actual_receipt_date:string|null;freight_amount:number;currency_code:string};
type PurchaseItem={purchase_order_id:string;line_subtotal:number};
type Supplier={id:string;supplier_name:string};
type PrintJob={print_job_id:string;job_number:string;order_number:string;customer_name:string;sku_code:string;product_name:string;quantity_base_units:number;due_date:string;status:string;qc_state:string};
type MoneyRow={key:string;label:string;currency:string;amount:number;count:number;quantity:number};
type MarginRow={key:string;label:string;currency:string;sales:number;cost:number;margin:number;quantity:number};
type StockRow={product_variant_id:string;onHand:number;reserved:number;available:number};

function validDate(value:string|undefined){return value&&/^\d{4}-\d{2}-\d{2}$/.test(value)?value:"";}
function money(value:number,currency:string){if(!currency||currency==="N/A")return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:2}).format(Number(value))+" "+currency;return new Intl.NumberFormat("vi-VN",{style:"currency",currency,maximumFractionDigits:currency==="VND"?0:2}).format(Number(value));}
function qty(value:number){return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));}
function day(value:string|null){if(!value)return "—";return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(value));}
function dateFilter(column:string,from:string,to:string){return (from?"&"+column+"=gte."+from:"")+(to?"&"+column+"=lte."+to:"");}
function addMoney(map:Map<string,MoneyRow>,key:string,label:string,currency:string,amount:number,quantity:number){const row=map.get(key)??{key,label,currency,amount:0,count:0,quantity:0};row.amount+=Number(amount);row.count+=1;row.quantity+=Number(quantity);map.set(key,row);}

export default async function ReportsPage({searchParams}:PageProps){
  const state=await searchParams;
  const from=validDate(state.from);
  const to=validDate(state.to);
  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const isSales=roles.has("SALES");
  const isAccounting=roles.has("ACCOUNTING");
  const isWarehouse=roles.has("WAREHOUSE");
  const isProduction=roles.has("PRINTER_PRODUCTION");
  const canSales=isOwner||isSales||isAccounting;
  const canFinance=isOwner||isAccounting;
  const canReceivables=isOwner||isSales||isAccounting;
  const canInventory=isOwner||isWarehouse;
  const canProduction=isOwner||isProduction;
  if(!canSales&&!canFinance&&!canReceivables&&!canInventory&&!canProduction)redirect("/");

  let orders:SalesOrder[]=[];
  let items:SalesItem[]=[];
  let customers:Customer[]=[];
  let variants:Variant[]=[];
  let products:Product[]=[];
  let costs:Cost[]=[];
  let receivables:Receivable[]=[];
  let payments:Payment[]=[];
  let paymentOrders:PaymentOrder[]=[];
  let movements:Movement[]=[];
  let purchases:Purchase[]=[];
  let purchaseItems:PurchaseItem[]=[];
  let suppliers:Supplier[]=[];
  let production:PrintJob[]=[];

  try{
    const requests:Promise<void>[]=[];
    if(canSales){
      requests.push((async()=>{
        orders=await supabaseRest<SalesOrder[]>("sales_orders?select=id,order_number,customer_id,order_status,order_date,currency_code&order_status=in.(CONFIRMED,COMPLETED)"+dateFilter("order_date",from,to)+"&order=order_date.desc&limit=5000");
        const ids=orders.map(row=>row.id);
        [customers,variants,products]=await Promise.all([
          supabaseRest<Customer[]>("customers?select=id,display_name&limit=5000"),
          supabaseRest<Variant[]>("product_variants?select=id,product_id,sku_code,minimum_stock_quantity,base_inventory_unit&limit=5000"),
          supabaseRest<Product[]>("products?select=id,name&limit=5000"),
        ]);
        if(ids.length)items=await supabaseRest<SalesItem[]>("sales_order_items?select=id,sales_order_id,product_variant_id,base_quantity,line_total,print_mode&sales_order_id=in.("+ids.join(",")+")&limit=10000");
      })());
    }
    if(canFinance){
      requests.push((async()=>{
        [costs,payments,purchases,purchaseItems,suppliers]=await Promise.all([
          supabaseRest<Cost[]>("purchase_cost_history?select=product_variant_id,effective_at,inventory_cost_basis_per_base_unit,currency_code&inventory_cost_basis_per_base_unit=not.is.null&order=effective_at.asc&limit=10000"),
          supabaseRest<Payment[]>("customer_payments?select=id,sales_order_id,amount,payment_date,payment_method,status,reference"+dateFilter("payment_date",from,to)+"&order=payment_date.desc&limit=5000"),
          supabaseRest<Purchase[]>("purchase_orders?select=id,po_number,supplier_id,status,order_date,actual_receipt_date,freight_amount,currency_code"+dateFilter("order_date",from,to)+"&order=order_date.desc&limit=5000"),
          supabaseRest<PurchaseItem[]>("purchase_order_items?select=purchase_order_id,line_subtotal&limit=10000"),
          supabaseRest<Supplier[]>("suppliers?select=id,supplier_name&limit=5000"),
        ]);
        const paymentOrderIds=[...new Set(payments.map(row=>row.sales_order_id).filter((id):id is string=>Boolean(id)))];
        if(paymentOrderIds.length)paymentOrders=await supabaseRest<PaymentOrder[]>("sales_orders?select=id,currency_code&id=in.("+paymentOrderIds.join(",")+")&limit=5000");
      })());
    }
    if(canReceivables){
      requests.push((async()=>{receivables=await supabaseRest<Receivable[]>("sales_receivable_followup?select=sales_order_id,order_number,customer_name,order_total_amount,valid_payment_amount,receivable_amount,currency_code,payment_status,order_date"+dateFilter("order_date",from,to)+"&order=order_date.desc&limit=5000");})());
    }
    if(canInventory){
      requests.push((async()=>{
        movements=await supabaseRest<Movement[]>("inventory_movements?select=id,product_variant_id,movement_type,quantity_delta_base_units,reference,reason,occurred_at&order=occurred_at.desc&limit=10000");
        if(!variants.length||!products.length){
          [variants,products]=await Promise.all([
            supabaseRest<Variant[]>("product_variants?select=id,product_id,sku_code,minimum_stock_quantity,base_inventory_unit&limit=5000"),
            supabaseRest<Product[]>("products?select=id,name&limit=5000"),
          ]);
        }
      })());
    }
    if(canProduction){
      requests.push((async()=>{production=await supabaseRest<PrintJob[]>("rpc/print_job_tracking",{method:"POST",body:JSON.stringify({p_print_job_id:null})});})());
    }
    await Promise.all(requests);
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");
    throw error;
  }

  const customerById=new Map(customers.map(row=>[row.id,row.display_name]));
  const variantById=new Map(variants.map(row=>[row.id,row]));
  const productById=new Map(products.map(row=>[row.id,row.name]));
  const orderById=new Map(orders.map(row=>[row.id,row]));
  const paymentCurrencyByOrder=new Map(paymentOrders.map(row=>[row.id,row.currency_code]));
  const supplierById=new Map(suppliers.map(row=>[row.id,row.supplier_name]));

  const byPeriod=new Map<string,MoneyRow>();
  const byCustomer=new Map<string,MoneyRow>();
  const byProduct=new Map<string,MoneyRow>();
  for(const item of items){
    const order=orderById.get(item.sales_order_id);
    if(!order)continue;
    const variant=variantById.get(item.product_variant_id);
    const product=variant?productById.get(variant.product_id):undefined;
    addMoney(byPeriod,order.order_date+"|"+order.currency_code,order.order_date,order.currency_code,item.line_total,item.base_quantity);
    addMoney(byCustomer,order.customer_id+"|"+order.currency_code,customerById.get(order.customer_id)??order.customer_id,order.currency_code,item.line_total,item.base_quantity);
    addMoney(byProduct,item.product_variant_id+"|"+order.currency_code,(variant?.sku_code??item.product_variant_id)+" · "+(product??"Product"),order.currency_code,item.line_total,item.base_quantity);
  }

  const costsByVariantCurrency=new Map<string,Cost[]>();
  for(const cost of costs){
    if(cost.inventory_cost_basis_per_base_unit==null)continue;
    const key=cost.product_variant_id+"|"+cost.currency_code;
    const list=costsByVariantCurrency.get(key)??[];
    list.push(cost);
    costsByVariantCurrency.set(key,list);
  }
  const marginMap=new Map<string,MarginRow>();
  let marginEligibleLines=0;
  if(canFinance){
    for(const item of items){
      if(item.print_mode!=="PLAIN")continue;
      const order=orderById.get(item.sales_order_id);
      if(!order)continue;
      const history=costsByVariantCurrency.get(item.product_variant_id+"|"+order.currency_code)??[];
      const cutoff=new Date(order.order_date+"T23:59:59Z").getTime();
      const eligible=history.filter(cost=>new Date(cost.effective_at).getTime()<=cutoff);
      const valid=eligible.length?eligible[eligible.length-1]:undefined;
      if(!valid||valid.inventory_cost_basis_per_base_unit==null)continue;
      marginEligibleLines++;
      const variant=variantById.get(item.product_variant_id);
      const label=(variant?.sku_code??item.product_variant_id)+" · "+(variant?productById.get(variant.product_id)??"Product":"Product");
      const key=item.product_variant_id+"|"+order.currency_code;
      const row=marginMap.get(key)??{key,label,currency:order.currency_code,sales:0,cost:0,margin:0,quantity:0};
      row.sales+=Number(item.line_total);
      row.cost+=Number(item.base_quantity)*Number(valid.inventory_cost_basis_per_base_unit);
      row.margin=row.sales-row.cost;
      row.quantity+=Number(item.base_quantity);
      marginMap.set(key,row);
    }
  }

  const paymentByCurrency=new Map<string,MoneyRow>();
  for(const payment of payments){
    const currency=payment.sales_order_id?paymentCurrencyByOrder.get(payment.sales_order_id)??"N/A":"N/A";
    addMoney(paymentByCurrency,currency,currency,currency,payment.status==="POSTED"?payment.amount:0,0);
  }

  const purchaseAmountByOrder=new Map<string,number>();
  for(const item of purchaseItems)purchaseAmountByOrder.set(item.purchase_order_id,(purchaseAmountByOrder.get(item.purchase_order_id)??0)+Number(item.line_subtotal));

  const stockByVariant=new Map<string,StockRow>();
  for(const variant of variants)stockByVariant.set(variant.id,{product_variant_id:variant.id,onHand:0,reserved:0,available:0});
  for(const movement of movements){
    const row=stockByVariant.get(movement.product_variant_id)??{product_variant_id:movement.product_variant_id,onHand:0,reserved:0,available:0};
    const amount=Number(movement.quantity_delta_base_units);
    if(["GOODS_RECEIPT","SALES_ISSUE","ADJUSTMENT_IN","ADJUSTMENT_OUT","STOCKTAKE_ADJUSTMENT"].includes(movement.movement_type))row.onHand+=amount;
    if(["SALES_RESERVATION","RESERVATION_RELEASE","SALES_ISSUE"].includes(movement.movement_type))row.reserved+=amount;
    row.available=row.onHand-row.reserved;
    stockByVariant.set(movement.product_variant_id,row);
  }
  const stockRows=[...stockByVariant.values()];
  const lowStock=stockRows.filter(row=>{const variant=variantById.get(row.product_variant_id);return variant?row.available<=Number(variant.minimum_stock_quantity):false;});
  const filteredMovements=movements.filter(row=>{
    const d=row.occurred_at.slice(0,10);
    return (!from||d>=from)&&(!to||d<=to);
  });

  const outstandingReceivables=receivables.filter(row=>Number(row.receivable_amount)>0);

  return <main className="app-shell">
    <header className="topbar">
      <div><p className="eyebrow">OPS-WEBAPP · OPS-062</p><h1>Reports</h1><p className="muted">Role-aware operational and management reports. Monetary totals remain separated by currency.</p></div>
      <div className="hero-actions"><Link href="/" className="button button-secondary">Dashboard</Link></div>
    </header>

    <section className="content-card">
      <form method="get" className="form-row">
        <label>From<input type="date" name="from" defaultValue={from}/></label>
        <label>To<input type="date" name="to" defaultValue={to}/></label>
        <button type="submit" className="button button-primary">Apply period</button>
        <Link href="/reports" className="button button-secondary">All time</Link>
      </form>
      <p className="muted">Period filters apply to sales order date, payment date, purchase order date and inventory movement time. Stock and production are current-state snapshots.</p>
    </section>

    {canSales?<section className="content-card">
      <h2>Sales by period</h2>
      <div className="table-wrap"><table><thead><tr><th>Date</th><th>Currency</th><th>Lines</th><th>Base qty</th><th>Sales</th></tr></thead><tbody>
        {[...byPeriod.values()].sort((a,b)=>b.label.localeCompare(a.label)).map(row=><tr key={row.key}><td>{row.label}</td><td>{row.currency}</td><td>{row.count}</td><td>{qty(row.quantity)}</td><td><strong>{money(row.amount,row.currency)}</strong></td></tr>)}
        {byPeriod.size===0?<tr><td colSpan={5} className="empty-state">Không có sales trong kỳ.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canSales?<section className="content-card">
      <h2>Sales by customer</h2>
      <div className="table-wrap"><table><thead><tr><th>Customer</th><th>Currency</th><th>Lines</th><th>Sales</th></tr></thead><tbody>
        {[...byCustomer.values()].sort((a,b)=>b.amount-a.amount).map(row=><tr key={row.key}><td>{row.label}</td><td>{row.currency}</td><td>{row.count}</td><td><strong>{money(row.amount,row.currency)}</strong></td></tr>)}
        {byCustomer.size===0?<tr><td colSpan={4} className="empty-state">Không có sales theo customer.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canSales?<section className="content-card">
      <h2>Sales by product</h2>
      <div className="table-wrap"><table><thead><tr><th>SKU / Product</th><th>Currency</th><th>Base qty</th><th>Sales</th></tr></thead><tbody>
        {[...byProduct.values()].sort((a,b)=>b.amount-a.amount).map(row=><tr key={row.key}><td>{row.label}</td><td>{row.currency}</td><td>{qty(row.quantity)}</td><td><strong>{money(row.amount,row.currency)}</strong></td></tr>)}
        {byProduct.size===0?<tr><td colSpan={4} className="empty-state">Không có sales theo product.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canFinance?<section className="content-card">
      <h2>Gross margin where cost data is valid</h2>
      <p className="muted">Chỉ PLAIN lines có inventory cost basis non-null, effective on/before order date và cùng currency. PRINTED lines không được suy đoán margin vì chưa có authoritative actual print-cost snapshot. Coverage: {marginEligibleLines}/{items.length} sales line(s).</p>
      <div className="table-wrap"><table><thead><tr><th>SKU / Product</th><th>Currency</th><th>Base qty</th><th>Sales</th><th>Authoritative cost</th><th>Gross margin</th></tr></thead><tbody>
        {[...marginMap.values()].sort((a,b)=>b.margin-a.margin).map(row=><tr key={row.key}><td>{row.label}</td><td>{row.currency}</td><td>{qty(row.quantity)}</td><td>{money(row.sales,row.currency)}</td><td>{money(row.cost,row.currency)}</td><td><strong>{money(row.margin,row.currency)}</strong></td></tr>)}
        {marginMap.size===0?<tr><td colSpan={6} className="empty-state">Chưa có sales line đủ authoritative cost basis để báo cáo gross margin.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canReceivables?<section className="content-card">
      <h2>Customer receivables</h2>
      <div className="table-wrap"><table><thead><tr><th>Order</th><th>Customer</th><th>Currency</th><th>Total</th><th>Paid</th><th>Receivable</th><th>Status</th></tr></thead><tbody>
        {outstandingReceivables.map(row=><tr key={row.sales_order_id}><td>{row.order_number}</td><td>{row.customer_name}</td><td>{row.currency_code}</td><td>{money(row.order_total_amount,row.currency_code)}</td><td>{money(row.valid_payment_amount,row.currency_code)}</td><td><strong>{money(row.receivable_amount,row.currency_code)}</strong></td><td>{row.payment_status}</td></tr>)}
        {outstandingReceivables.length===0?<tr><td colSpan={7} className="empty-state">Không có receivable đang mở trong kỳ.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canFinance?<section className="content-card">
      <h2>Customer payments</h2>
      <div className="metric-grid">{[...paymentByCurrency.values()].map(row=><article className="metric-card" key={row.key}><span>POSTED · {row.currency}</span><strong>{money(row.amount,row.currency)}</strong></article>)}</div>
      <div className="table-wrap"><table><thead><tr><th>Date</th><th>Reference</th><th>Method</th><th>Status</th><th>Amount</th></tr></thead><tbody>
        {payments.map(row=>{const currency=row.sales_order_id?paymentCurrencyByOrder.get(row.sales_order_id)??"N/A":"N/A";return <tr key={row.id}><td>{day(row.payment_date)}</td><td>{row.reference??row.id}</td><td>{row.payment_method}</td><td>{row.status}</td><td>{money(row.amount,currency)}</td></tr>;})}
        {payments.length===0?<tr><td colSpan={5} className="empty-state">Không có payment trong kỳ.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canFinance?<section className="content-card">
      <h2>Purchase history</h2>
      <div className="table-wrap"><table><thead><tr><th>PO</th><th>Supplier</th><th>Date</th><th>Status</th><th>Receipt</th><th>Currency</th><th>Total</th></tr></thead><tbody>
        {purchases.map(row=>{const total=(purchaseAmountByOrder.get(row.id)??0)+Number(row.freight_amount);return <tr key={row.id}><td>{row.po_number}</td><td>{supplierById.get(row.supplier_id)??row.supplier_id}</td><td>{row.order_date}</td><td>{row.status}</td><td>{row.actual_receipt_date??"—"}</td><td>{row.currency_code}</td><td><strong>{money(total,row.currency_code)}</strong></td></tr>;})}
        {purchases.length===0?<tr><td colSpan={7} className="empty-state">Không có purchase order trong kỳ.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canInventory?<section className="content-card">
      <h2>Inventory on hand / reserved / available</h2>
      <div className="table-wrap"><table><thead><tr><th>SKU / Product</th><th>Unit</th><th>On hand</th><th>Reserved</th><th>Available</th><th>Minimum</th></tr></thead><tbody>
        {stockRows.map(row=>{const variant=variantById.get(row.product_variant_id);const product=variant?productById.get(variant.product_id):undefined;return <tr key={row.product_variant_id}><td>{variant?.sku_code??row.product_variant_id}<div className="subtle">{product??"—"}</div></td><td>{variant?.base_inventory_unit??"—"}</td><td>{qty(row.onHand)}</td><td>{qty(row.reserved)}</td><td><strong>{qty(row.available)}</strong></td><td>{qty(variant?.minimum_stock_quantity??0)}</td></tr>;})}
        {stockRows.length===0?<tr><td colSpan={6} className="empty-state">Chưa có stock snapshot.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canInventory?<section className="content-card">
      <h2>Low stock</h2>
      <div className="table-wrap"><table><thead><tr><th>SKU / Product</th><th>Minimum</th><th>On hand</th><th>Reserved</th><th>Available</th></tr></thead><tbody>
        {lowStock.map(row=>{const variant=variantById.get(row.product_variant_id);return <tr key={row.product_variant_id}><td>{variant?.sku_code??row.product_variant_id}<div className="subtle">{variant?productById.get(variant.product_id)??"—":"—"}</div></td><td>{qty(variant?.minimum_stock_quantity??0)}</td><td>{qty(row.onHand)}</td><td>{qty(row.reserved)}</td><td><strong>{qty(row.available)}</strong></td></tr>;})}
        {lowStock.length===0?<tr><td colSpan={5} className="empty-state">Không có SKU low-stock.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canInventory?<section className="content-card">
      <h2>Inventory movements</h2>
      <div className="table-wrap"><table><thead><tr><th>Time</th><th>SKU / Product</th><th>Type</th><th>Quantity delta</th><th>Reference / Reason</th></tr></thead><tbody>
        {filteredMovements.map(row=>{const variant=variantById.get(row.product_variant_id);return <tr key={row.id}><td>{day(row.occurred_at)}</td><td>{variant?.sku_code??row.product_variant_id}<div className="subtle">{variant?productById.get(variant.product_id)??"—":"—"}</div></td><td>{row.movement_type}</td><td>{qty(row.quantity_delta_base_units)}</td><td>{row.reference??"—"}<div className="subtle">{row.reason??"—"}</div></td></tr>;})}
        {filteredMovements.length===0?<tr><td colSpan={5} className="empty-state">Không có inventory movement trong kỳ.</td></tr>:null}
      </tbody></table></div>
    </section>:null}

    {canProduction?<section className="content-card">
      <h2>Production workload / status</h2>
      <p className="muted">{isOwner?"Owner/Admin sees all authorized print jobs.":"PRINTER / PRODUCTION sees only jobs assigned to the current account; no financial fields are queried."}</p>
      <div className="table-wrap"><table><thead><tr><th>Job</th><th>Order / Customer</th><th>SKU / Product</th><th>Qty</th><th>Due</th><th>Status / QC</th></tr></thead><tbody>
        {production.map(row=><tr key={row.print_job_id}><td>{row.job_number}</td><td>{row.order_number}<div className="subtle">{row.customer_name}</div></td><td>{row.sku_code}<div className="subtle">{row.product_name}</div></td><td>{qty(row.quantity_base_units)}</td><td>{day(row.due_date)}</td><td><strong>{row.status}</strong><div className="subtle">QC {row.qc_state}</div></td></tr>)}
        {production.length===0?<tr><td colSpan={6} className="empty-state">Không có production workload.</td></tr>:null}
      </tbody></table></div>
    </section>:null}
  </main>;
}

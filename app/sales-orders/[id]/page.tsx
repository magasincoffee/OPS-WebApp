import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Order={id:string;order_number:string;customer_id:string;source_quotation_id:string|null;order_status:string;print_status:string;warehouse_status:string;payment_status:string;delivery_status:string;requested_due_date:string|null;currency_code:string;notes:string|null};
type Customer={id:string;display_name:string};
type Product={id:string;name:string};
type Variant={id:string;product_id:string;sku_code:string;variant_name:string|null;base_inventory_unit:string};
type Packaging={id:string;product_variant_id:string;package_name:string;units_per_package:number};
type Item={id:string;product_variant_id:string;sale_unit:string;sale_quantity:number;base_quantity:number;unit_price_per_sale_unit:number;discount_amount:number;line_total:number;print_mode:string;print_color_count:number|null;print_specification:string|null;pricing_rule_id:string|null};
type Total={sales_order_id:string;subtotal_amount:number;discount_amount:number;total_amount:number;currency_code:string};
type Rule={id:string;name:string};
type PageProps={params:Promise<{id:string}>;searchParams:Promise<{action?:string;error?:string}>};

function money(value:number,currency:string){return new Intl.NumberFormat("vi-VN",{style:"currency",currency,maximumFractionDigits:currency==="VND"?0:2}).format(Number(value));}
function num(value:number){return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));}

export default async function SalesOrderDetailPage({params,searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const canManage=roles.has("OWNER_ADMIN")||roles.has("SALES");
  const canView=canManage||roles.has("ACCOUNTING");
  if(!canView)redirect("/sales-orders");
  const {id}=await params; const state=await searchParams;

  let orders:Order[],customers:Customer[],products:Product[],variants:Variant[],packages:Packaging[],items:Item[],totals:Total[],rules:Rule[];
  try{
    [orders,customers,products,variants,packages,items,totals,rules]=await Promise.all([
      supabaseRest<Order[]>(`sales_orders?id=eq.${encodeURIComponent(id)}&select=id,order_number,customer_id,source_quotation_id,order_status,print_status,warehouse_status,payment_status,delivery_status,requested_due_date,currency_code,notes`),
      supabaseRest<Customer[]>("customers?select=id,display_name&limit=2000"),
      supabaseRest<Product[]>("products?select=id,name&limit=2000"),
      supabaseRest<Variant[]>("product_variants?select=id,product_id,sku_code,variant_name,base_inventory_unit&is_active=eq.true&order=sku_code.asc&limit=5000"),
      supabaseRest<Packaging[]>("product_packaging?select=id,product_variant_id,package_name,units_per_package&is_active=eq.true&order=package_name.asc&limit=5000"),
      supabaseRest<Item[]>(`sales_order_items?sales_order_id=eq.${encodeURIComponent(id)}&select=id,product_variant_id,sale_unit,sale_quantity,base_quantity,unit_price_per_sale_unit,discount_amount,line_total,print_mode,print_color_count,print_specification,pricing_rule_id&order=created_at.asc&limit=500`),
      supabaseRest<Total[]>(`sales_order_totals?sales_order_id=eq.${encodeURIComponent(id)}&select=sales_order_id,subtotal_amount,discount_amount,total_amount,currency_code`),
      supabaseRest<Rule[]>("pricing_rules?select=id,name&limit=2000"),
    ]);
  }catch(error){if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");throw error;}
  const order=orders[0]; if(!order)notFound();
  const customerById=new Map(customers.map(x=>[x.id,x])); const productById=new Map(products.map(x=>[x.id,x])); const variantById=new Map(variants.map(x=>[x.id,x])); const ruleById=new Map(rules.map(x=>[x.id,x]));
  const packageByVariant=new Map<string,Packaging[]>(); for(const p of packages){const g=packageByVariant.get(p.product_variant_id)??[];g.push(p);packageByVariant.set(p.product_variant_id,g);}
  const total=totals[0]??{sales_order_id:order.id,subtotal_amount:0,discount_amount:0,total_amount:0,currency_code:order.currency_code};
  const printedLineCount=items.filter(item=>item.print_mode==="PRINTED").length;
  const plainLineCount=items.length-printedLineCount;
  const printBranch=printedLineCount===0?"PLAIN_BYPASS":plainLineCount===0?"PRINTED":"MIXED";

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-033</p><h1>{order.order_number}</h1><p className="muted">{customerById.get(order.customer_id)?.display_name??"Customer"} · {order.order_status}</p></div><div className="hero-actions"><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link>{roles.has("OWNER_ADMIN")||roles.has("ACCOUNTING")?<Link href="/payments" className="button button-secondary">Payments</Link>:null}<Link href="/deliveries" className="button button-secondary">Deliveries</Link><Link href="/inventory" className="button button-secondary">Inventory</Link></div></header>
    {state.action?<section className="content-card"><p className="permission-note">Sales-order action completed: {state.action}.</p></section>:null}
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất thao tác ({state.error}).</p></section>:null}

    <section className="metric-grid"><article className="metric-card"><span>Order</span><strong>{order.order_status}</strong></article><article className="metric-card"><span>Warehouse</span><strong>{order.warehouse_status}</strong></article><article className="metric-card"><span>Print</span><strong>{order.print_status}</strong><div className="subtle">{printBranch}</div></article><article className="metric-card"><span>Total</span><strong className="metric-small">{money(total.total_amount,total.currency_code)}</strong></article></section>

    <section className="content-card"><div className="section-heading"><div><h2>Lifecycle</h2><p className="muted">Payment {order.payment_status} · Delivery {order.delivery_status}</p></div>{canManage?<div className="hero-actions">
      {order.order_status==="DRAFT"&&items.length>0?<form action="/api/sales-orders/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="sales_order_id" value={order.id}/><input type="hidden" name="status" value="CONFIRMED"/><button className="button button-primary" type="submit">{printedLineCount>0?"Confirm · route PRINTED lines":"Confirm · bypass print"}</button></form>:null}
      {order.order_status==="DRAFT"||order.order_status==="CONFIRMED"?<form action="/api/sales-orders/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="sales_order_id" value={order.id}/><input type="hidden" name="status" value="CANCELLED"/><button className="button button-secondary" type="submit">Cancel</button></form>:null}
      {order.order_status==="CONFIRMED"?<form action="/api/sales-orders/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="sales_order_id" value={order.id}/><input type="hidden" name="status" value="COMPLETED"/><button className="button button-secondary" type="submit">Complete when eligible</button></form>:null}
    </div>:null}</div><p className="muted">OPS-032 branch: {printedLineCount===0?"toàn bộ line PLAIN — production được bypass và print status sẽ là NOT_REQUIRED":`${printedLineCount} PRINTED line(s) — khi confirm, print status sẽ là WAITING; ${plainLineCount} PLAIN line(s) vẫn bypass production`}. CONFIRMED đồng thời mở OPS-023 reservation. Print-job materialization và production transitions thuộc OPS-040+.</p></section>

    <section className="content-card"><h2>Order lines</h2><div className="table-wrap"><table><thead><tr><th>SKU</th><th>Qty</th><th>Print</th><th>Unit price</th><th>Discount</th><th>Total</th><th>Pricing</th><th></th></tr></thead><tbody>
      {items.map(item=>{const variant=variantById.get(item.product_variant_id);return <tr key={item.id}><td><strong>{variant?.sku_code??item.product_variant_id}</strong><div className="subtle">{productById.get(variant?.product_id??"")?.name??""}</div></td><td>{num(item.sale_quantity)} {item.sale_unit}<div className="subtle">{num(item.base_quantity)} base</div></td><td>{item.print_mode}{item.print_color_count?<div className="subtle">{item.print_color_count} color(s)</div>:null}</td><td>{money(item.unit_price_per_sale_unit,order.currency_code)}</td><td>{money(item.discount_amount,order.currency_code)}</td><td>{money(item.line_total,order.currency_code)}</td><td>{item.pricing_rule_id?ruleById.get(item.pricing_rule_id)?.name??"Rule":"Snapshot"}</td><td>{canManage&&order.order_status==="DRAFT"?<form action="/api/sales-orders/operations" method="post"><input type="hidden" name="operation" value="remove_item"/><input type="hidden" name="sales_order_id" value={order.id}/><input type="hidden" name="sales_order_item_id" value={item.id}/><button type="submit" className="button button-secondary">Xóa</button></form>:null}</td></tr>;})}
      {items.length===0?<tr><td colSpan={8} className="empty-state">Chưa có line.</td></tr>:null}
    </tbody></table></div></section>

    {canManage&&order.order_status==="DRAFT"?<section className="content-card"><h2>Thêm direct-order line</h2><form action="/api/sales-orders/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="add_item"/><input type="hidden" name="sales_order_id" value={order.id}/><label>SKU / sale unit *<select name="sale_source" required defaultValue=""><option value="" disabled>Chọn SKU / unit</option>{variants.map(v=><optgroup key={v.id} label={`${v.sku_code} · ${productById.get(v.product_id)?.name??""}`}><option value={`${v.id}|`}>Base unit · {v.base_inventory_unit}</option>{(packageByVariant.get(v.id)??[]).map(p=><option key={p.id} value={`${v.id}|${p.id}`}>{p.package_name} ({num(p.units_per_package)} {v.base_inventory_unit})</option>)}</optgroup>)}</select></label><div className="form-row"><label>Sale quantity *<input type="number" name="sale_quantity" min="0.000001" step="any" required/></label><label>Discount<input type="number" name="discount_amount" min="0" step="any" defaultValue="0"/></label></div><div className="form-row"><label>Print mode<select name="print_mode" defaultValue="PLAIN"><option value="PLAIN">PLAIN</option><option value="PRINTED">PRINTED</option></select></label><label>Print colors<input type="number" name="print_color_count" min="1" step="1"/></label></div><label>Print specification<textarea name="print_specification" rows={2}/></label><div className="form-row"><label>Artwork reference<input name="artwork_reference"/></label><label>Requested due date<input type="date" name="requested_due_date"/></label></div><label>Notes<textarea name="notes" rows={2}/></label><button type="submit" className="button button-primary">Thêm line theo pricing rule</button></form></section>:null}
  </main>;
}

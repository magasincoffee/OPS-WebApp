import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Tracking={
  delivery_id:string;delivery_number:string;sales_order_id:string;order_number:string;customer_name:string;
  status:string;consignee_name:string;consignee_phone:string|null;consignee_address:string|null;parcel_info:string|null;
  carrier_note:string|null;delivery_reference:string|null;ready_at:string|null;dispatch_date:string|null;completed_at:string|null;notes:string|null;
};
type Manifest={delivery_item_id:string;sales_order_item_id:string;product_variant_id:string;sku_code:string;product_name:string;quantity_base_units:number;base_inventory_unit:string};
type PageProps={params:Promise<{id:string}>;searchParams:Promise<{action?:string;error?:string}>};

function date(value:string|null){
  if(!value)return "—";
  return new Intl.DateTimeFormat("vi-VN",{dateStyle:"short"}).format(new Date(`${value}T00:00:00`));
}
function num(value:number){return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));}

export default async function DeliveryDetailPage({params,searchParams}:PageProps){
  const roles=await getCurrentRoles();
  const canManage=roles.has("OWNER_ADMIN")||roles.has("WAREHOUSE");
  const canView=canManage||roles.has("SALES");
  if(!canView)redirect("/");
  const {id}=await params; const state=await searchParams;

  let rows:Tracking[],manifest:Manifest[];
  try{
    [rows,manifest]=await Promise.all([
      supabaseRest<Tracking[]>("rpc/delivery_tracking",{method:"POST",body:JSON.stringify({p_delivery_id:id})}),
      supabaseRest<Manifest[]>("rpc/delivery_manifest",{method:"POST",body:JSON.stringify({p_delivery_id:id})}),
    ]);
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401)redirect("/login?error=session");
    throw error;
  }
  const delivery=rows[0]; if(!delivery)notFound();

  return <main className="app-shell">
    <header className="topbar"><div><p className="eyebrow">OPS-WEBAPP · OPS-033</p><h1>{delivery.delivery_number}</h1><p className="muted">{delivery.order_number} · {delivery.customer_name} · {delivery.status}</p></div><div className="hero-actions"><Link href="/deliveries" className="button button-secondary">Deliveries</Link><Link href="/sales-orders" className="button button-secondary">Sales Orders</Link></div></header>
    {state.action?<section className="content-card"><p className="permission-note">Delivery action completed: {state.action}.</p></section>:null}
    {state.error?<section className="content-card"><p className="permission-note">Không thể hoàn tất thao tác ({state.error}). Kiểm tra warehouse/print readiness và thông tin vận chuyển.</p></section>:null}

    <section className="metric-grid"><article className="metric-card"><span>Status</span><strong>{delivery.status}</strong></article><article className="metric-card"><span>Ready</span><strong className="metric-small">{delivery.ready_at?"YES":"NO"}</strong></article><article className="metric-card"><span>Dispatch</span><strong className="metric-small">{date(delivery.dispatch_date)}</strong></article><article className="metric-card"><span>Completed</span><strong className="metric-small">{delivery.completed_at?"YES":"NO"}</strong></article></section>

    <section className="content-card"><h2>Shipment manifest</h2><div className="table-wrap"><table><thead><tr><th>SKU</th><th>Product</th><th>Quantity</th></tr></thead><tbody>{manifest.map(item=><tr key={item.delivery_item_id}><td><strong>{item.sku_code}</strong></td><td>{item.product_name}</td><td>{num(item.quantity_base_units)} {item.base_inventory_unit}</td></tr>)}</tbody></table></div></section>

    <section className={canManage?"dashboard-grid":"content-card"}>
      <article className="content-card"><h2>Delivery details</h2><p><strong>Consignee:</strong> {delivery.consignee_name}</p><p><strong>Phone:</strong> {delivery.consignee_phone??"—"}</p><p><strong>Address:</strong> {delivery.consignee_address??"—"}</p><p><strong>Parcel:</strong> {delivery.parcel_info??"—"}</p><p><strong>Carrier/chành xe:</strong> {delivery.carrier_note??"—"}</p><p><strong>Reference:</strong> {delivery.delivery_reference??"—"}</p><p><strong>Notes:</strong> {delivery.notes??"—"}</p></article>
      {canManage&&["NOT_READY","READY_TO_SHIP"].includes(delivery.status)?<aside className="content-card"><h2>Cập nhật operational details</h2><form action="/api/deliveries/operations" method="post" className="form-stack"><input type="hidden" name="operation" value="update_details"/><input type="hidden" name="delivery_id" value={delivery.delivery_id}/><label>Consignee *<input name="consignee_name" required defaultValue={delivery.consignee_name}/></label><div className="form-row"><label>Phone<input name="consignee_phone" defaultValue={delivery.consignee_phone??""}/></label><label>Address<input name="consignee_address" defaultValue={delivery.consignee_address??""}/></label></div><label>Parcel/package info<textarea name="parcel_info" rows={2} defaultValue={delivery.parcel_info??""}/></label><div className="form-row"><label>Carrier/chành xe<input name="carrier_note" defaultValue={delivery.carrier_note??""}/></label><label>Delivery reference<input name="delivery_reference" defaultValue={delivery.delivery_reference??""}/></label></div><label>Notes<textarea name="notes" rows={2} defaultValue={delivery.notes??""}/></label><button type="submit" className="button button-secondary">Lưu details</button></form></aside>:null}
    </section>

    {canManage?<section className="content-card"><div className="section-heading"><div><h2>Lifecycle</h2><p className="muted">NOT_READY → READY_TO_SHIP → DISPATCHED → COMPLETED. Chỉ được cancel trước dispatch.</p></div><div className="hero-actions">
      {delivery.status==="NOT_READY"?<><form action="/api/deliveries/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="delivery_id" value={delivery.delivery_id}/><input type="hidden" name="status" value="READY_TO_SHIP"/><button type="submit" className="button button-primary">Mark READY_TO_SHIP</button></form><form action="/api/deliveries/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="delivery_id" value={delivery.delivery_id}/><input type="hidden" name="status" value="CANCELLED"/><button type="submit" className="button button-secondary">Cancel</button></form></>:null}
      {delivery.status==="READY_TO_SHIP"?<><form action="/api/deliveries/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="delivery_id" value={delivery.delivery_id}/><input type="hidden" name="status" value="DISPATCHED"/><label>Dispatch date<input type="date" name="dispatch_date"/></label><button type="submit" className="button button-primary">Dispatch</button></form><form action="/api/deliveries/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="delivery_id" value={delivery.delivery_id}/><input type="hidden" name="status" value="CANCELLED"/><button type="submit" className="button button-secondary">Cancel</button></form></>:null}
      {delivery.status==="DISPATCHED"?<form action="/api/deliveries/operations" method="post"><input type="hidden" name="operation" value="status"/><input type="hidden" name="delivery_id" value={delivery.delivery_id}/><input type="hidden" name="status" value="COMPLETED"/><button type="submit" className="button button-primary">Mark COMPLETED</button></form>:null}
    </div></div></section>:null}
  </main>;
}

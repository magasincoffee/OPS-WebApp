import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type PurchaseOrder = {
  id:string; po_number:string; supplier_id:string; status:string; order_date:string;
  expected_receipt_date:string|null; actual_receipt_date:string|null;
  freight_amount:number; currency_code:string; payment_note:string|null;
  document_reference:string|null; responsible_user_id:string|null; notes:string|null;
};

type Supplier={id:string;supplier_name:string};
type Item={
  id:string;product_variant_id:string;packaging_id:string|null;purchase_unit:string;
  package_quantity:number;units_per_purchase_unit:number;base_quantity:number;
  unit_cost_per_purchase_unit:number;line_subtotal:number;notes:string|null;
};
type Payment={
  id:string;amount:number;payment_date:string;payment_method:string|null;reference:string|null;
  evidence_attachment_id:string|null;notes:string|null;created_at:string;
};
type Variant={id:string;product_id:string;sku_code:string;variant_name:string|null;base_inventory_unit:string;is_active:boolean};
type Product={id:string;name:string};
type Packaging={id:string;product_variant_id:string;package_name:string;units_per_package:number;is_active:boolean};
type User={id:string;display_name:string|null;is_active:boolean};
type Attachment={id:string;attachment_kind:string;original_file_name:string;media_type:string|null;size_bytes:number|null;created_at:string;metadata:Record<string,unknown>};

type PageProps={
  params:Promise<{id:string}>;
  searchParams:Promise<{
    created?:string;saved?:string;item_saved?:string;payment_saved?:string;
    attachment_saved?:string;payment_id?:string;error?:string;
  }>;
};

function money(value:number,currency:string){
  try{
    return new Intl.NumberFormat("vi-VN",{style:"currency",currency,maximumFractionDigits:currency==="VND"?0:2}).format(Number(value));
  }catch{
    return `${Number(value).toLocaleString("vi-VN")} ${currency}`;
  }
}

function num(value:number){
  return new Intl.NumberFormat("vi-VN",{maximumFractionDigits:6}).format(Number(value));
}

export default async function PurchaseOrderPage({params,searchParams}:PageProps){
  const accessToken=await getAccessToken();
  if(!accessToken) redirect("/login");

  const roles=await getCurrentRoles();
  const isOwner=roles.has("OWNER_ADMIN");
  const canView=isOwner||roles.has("ACCOUNTING");
  if(!canView) redirect("/purchases");

  const {id}=await params;
  const state=await searchParams;
  const encoded=encodeURIComponent(id);

  let orders:PurchaseOrder[];
  try{
    orders=await supabaseRest<PurchaseOrder[]>(
      `purchase_orders?id=eq.${encoded}&select=id,po_number,supplier_id,status,order_date,expected_receipt_date,actual_receipt_date,freight_amount,currency_code,payment_note,document_reference,responsible_user_id,notes`
    );
  }catch(error){
    if(error instanceof SupabaseRestError&&error.status===401) redirect("/login?error=session");
    throw error;
  }
  const order=orders[0];
  if(!order) notFound();

  const [supplierRows,items,payments,attachments]=await Promise.all([
    supabaseRest<Supplier[]>(`suppliers?id=eq.${encodeURIComponent(order.supplier_id)}&select=id,supplier_name`),
    supabaseRest<Item[]>(`purchase_order_items?purchase_order_id=eq.${encoded}&select=id,product_variant_id,packaging_id,purchase_unit,package_quantity,units_per_purchase_unit,base_quantity,unit_cost_per_purchase_unit,line_subtotal,notes&order=created_at.asc&limit=1000`),
    supabaseRest<Payment[]>(`purchase_payments?purchase_order_id=eq.${encoded}&select=id,amount,payment_date,payment_method,reference,evidence_attachment_id,notes,created_at&order=payment_date.asc,created_at.asc&limit=500`),
    supabaseRest<Attachment[]>(`attachments?linked_entity_type=eq.PURCHASE_ORDER&linked_entity_id=eq.${encoded}&select=id,attachment_kind,original_file_name,media_type,size_bytes,created_at,metadata&order=created_at.desc&limit=500`)
  ]);

  const allVariants=isOwner
    ? await supabaseRest<Variant[]>("product_variants?select=id,product_id,sku_code,variant_name,base_inventory_unit,is_active&is_active=eq.true&order=sku_code.asc&limit=2000")
    : [];
  const referencedIds=[...new Set([...items.map((i)=>i.product_variant_id),...allVariants.map((v)=>v.id)])];
  const variants=referencedIds.length
    ? await supabaseRest<Variant[]>(`product_variants?id=in.(${referencedIds.join(",")})&select=id,product_id,sku_code,variant_name,base_inventory_unit,is_active`)
    : [];
  const productIds=[...new Set(variants.map((v)=>v.product_id))];
  const products=productIds.length
    ? await supabaseRest<Product[]>(`products?id=in.(${productIds.join(",")})&select=id,name`)
    : [];
  const packaging=isOwner
    ? await supabaseRest<Packaging[]>("product_packaging?select=id,product_variant_id,package_name,units_per_package,is_active&is_active=eq.true&order=package_name.asc&limit=5000")
    : (items.some((i)=>i.packaging_id)
      ? await supabaseRest<Packaging[]>(`product_packaging?id=in.(${items.filter((i)=>i.packaging_id).map((i)=>i.packaging_id).join(",")})&select=id,product_variant_id,package_name,units_per_package,is_active`)
      : []);
  const users=isOwner
    ? await supabaseRest<User[]>("users?select=id,display_name,is_active&is_active=eq.true&order=display_name.asc&limit=500")
    : (order.responsible_user_id
      ? await supabaseRest<User[]>(`users?id=eq.${encodeURIComponent(order.responsible_user_id)}&select=id,display_name,is_active`)
      : []);

  const variantsById=new Map(variants.map((v)=>[v.id,v]));
  const productsById=new Map(products.map((p)=>[p.id,p]));
  const packagingById=new Map(packaging.map((p)=>[p.id,p]));
  const usersById=new Map(users.map((u)=>[u.id,u]));
  const itemSubtotal=items.reduce((sum,item)=>sum+Number(item.line_subtotal),0);
  const total=itemSubtotal+Number(order.freight_amount);
  const paid=payments.reduce((sum,payment)=>sum+Number(payment.amount),0);
  const outstanding=Math.max(0,total-paid);
  const paymentState=total>0&&paid>=total-0.000001?"PAID":paid>0?"PARTIALLY_PAID":"UNPAID";
  const supplier=supplierRows[0];

  return(
    <main className="app-shell">
      <header className="topbar">
        <div>
          <Link href="/purchases" className="text-link">← Purchase Orders</Link>
          <p className="eyebrow">PURCHASE ORDER</p>
          <h1>{order.po_number}</h1>
          <p className="muted">{supplier?.supplier_name??"Supplier"} · {order.status} · {paymentState}</p>
        </div>
        <form action="/api/auth/logout" method="post">
          <button className="button button-secondary" type="submit">Đăng xuất</button>
        </form>
      </header>

      {state.created||state.saved||state.item_saved||state.payment_saved||state.attachment_saved
        ? <div className="alert alert-success">Đã lưu purchase-order workflow.</div>:null}
      {state.error
        ? <div className="alert alert-error">
            {state.error==="payment_exceeds_total"
              ?"Payment vượt số tiền còn phải trả hoặc PO chưa có tổng tiền."
              :state.error==="packaging_mismatch"
                ?"Packaging không thuộc SKU đã chọn."
                :state.error==="cancelled"
                  ?"PO đã CANCELLED nên không nhận thêm line/payment."
                  :"Không thể lưu. Kiểm tra dữ liệu hoặc quyền OWNER/ADMIN."}
          </div>:null}

      <section className="metric-grid">
        <article className="metric-card"><span>Item subtotal</span><strong className="metric-small">{money(itemSubtotal,order.currency_code)}</strong></article>
        <article className="metric-card"><span>Freight/logistics</span><strong className="metric-small">{money(order.freight_amount,order.currency_code)}</strong></article>
        <article className="metric-card"><span>PO total</span><strong className="metric-small">{money(total,order.currency_code)}</strong></article>
        <article className="metric-card"><span>Outstanding</span><strong className="metric-small">{money(outstanding,order.currency_code)}</strong></article>
      </section>

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>PO header</h2>
          {isOwner?(
            <form action={`/api/purchases/${order.id}`} method="post" className="form-stack">
              <div className="form-row">
                <label>Status
                  <select name="status" defaultValue={order.status}>
                    {![ "DRAFT","ORDERED","CANCELLED" ].includes(order.status)?<option value={order.status}>{order.status} (downstream)</option>:null}
                    <option value="DRAFT">DRAFT</option>
                    <option value="ORDERED">ORDERED</option>
                    <option value="CANCELLED">CANCELLED</option>
                  </select>
                </label>
                <label>Responsible user
                  <select name="responsible_user_id" defaultValue={order.responsible_user_id??""}>
                    <option value="">Chưa phân công</option>
                    {users.map((u)=><option key={u.id} value={u.id}>{u.display_name??u.id}</option>)}
                  </select>
                </label>
              </div>
              <div className="form-row">
                <label>Order date<input type="date" name="order_date" defaultValue={order.order_date} required /></label>
                <label>Expected receipt<input type="date" name="expected_receipt_date" defaultValue={order.expected_receipt_date??""} /></label>
              </div>
              <div className="form-row">
                <label>Freight/logistics<input type="number" step="any" min="0" name="freight_amount" defaultValue={order.freight_amount} /></label>
                <label>Currency<input name="currency_code" defaultValue={order.currency_code} pattern="[A-Za-z]{3}" required /></label>
              </div>
              <label>Document reference<input name="document_reference" defaultValue={order.document_reference??""} /></label>
              <label>Payment note<textarea name="payment_note" rows={2} defaultValue={order.payment_note??""} /></label>
              <label>Notes<textarea name="notes" rows={2} defaultValue={order.notes??""} /></label>
              <button className="button button-primary" type="submit">Lưu PO</button>
            </form>
          ):(
            <div className="stack-list">
              <div className="stack-item"><span>Order date</span><strong>{order.order_date}</strong></div>
              <div className="stack-item"><span>Expected receipt</span><strong>{order.expected_receipt_date??"—"}</strong></div>
              <div className="stack-item"><span>Actual receipt</span><strong>{order.actual_receipt_date??"Chưa nhận hàng"}</strong></div>
              <div className="stack-item"><span>Responsible</span><strong>{usersById.get(order.responsible_user_id??"")?.display_name??order.responsible_user_id??"—"}</strong></div>
              <div className="stack-item"><span>Document reference</span><strong>{order.document_reference??"—"}</strong></div>
            </div>
          )}
        </article>

        <aside className="content-card">
          <h2>Supplier payment</h2>
          <div className="stack-item"><span>Payment state</span><strong>{paymentState}</strong></div>
          <div className="stack-item"><span>Paid</span><strong>{money(paid,order.currency_code)}</strong></div>
          <div className="stack-item"><span>Outstanding</span><strong>{money(outstanding,order.currency_code)}</strong></div>
          <p className="muted">V1 không quản lý supplier AP/debt. PO phải được thanh toán ngay; lịch sử payment được giữ làm bằng chứng.</p>
          {isOwner&&outstanding>0&&order.status!=="CANCELLED"?(
            <form action={`/api/purchases/${order.id}/payments`} method="post" className="form-stack">
              <label>Amount *<input type="number" step="any" min="0.000001" max={outstanding} name="amount" defaultValue={outstanding} required /></label>
              <label>Payment date *<input type="date" name="payment_date" defaultValue={new Date().toISOString().slice(0,10)} required /></label>
              <label>Method<input name="payment_method" placeholder="Bank transfer, cash..." /></label>
              <label>Reference<input name="reference" /></label>
              <label>Notes<textarea name="notes" rows={2} /></label>
              <button className="button button-primary" type="submit">Ghi nhận supplier payment</button>
            </form>
          ):null}
        </aside>
      </section>

      <section className="content-card">
        <h2>Order lines</h2>
        <div className="table-wrap">
          <table>
            <thead><tr><th>SKU</th><th>Packaging</th><th>Package qty</th><th>Conversion</th><th>Base qty</th><th>Unit cost</th><th>Subtotal</th></tr></thead>
            <tbody>
              {items.map((item)=>{
                const variant=variantsById.get(item.product_variant_id);
                const product=variant?productsById.get(variant.product_id):undefined;
                const pack=item.packaging_id?packagingById.get(item.packaging_id):undefined;
                return(
                  <tr key={item.id}>
                    <td><strong>{variant?.sku_code??"—"}</strong><div className="subtle">{product?.name??variant?.variant_name??"—"}</div></td>
                    <td>{pack?.package_name??item.purchase_unit}</td>
                    <td>{num(item.package_quantity)}</td>
                    <td>1 {item.purchase_unit} = {num(item.units_per_purchase_unit)} {variant?.base_inventory_unit??"base units"}</td>
                    <td>{num(item.base_quantity)}</td>
                    <td>{money(item.unit_cost_per_purchase_unit,order.currency_code)}</td>
                    <td>{money(item.line_subtotal,order.currency_code)}</td>
                  </tr>
                );
              })}
              {items.length===0?<tr><td colSpan={7} className="empty-state">Chưa có line item.</td></tr>:null}
            </tbody>
          </table>
        </div>

        {isOwner&&order.status!=="CANCELLED"?(
          <>
            <h3>Thêm line item</h3>
            <form action={`/api/purchases/${order.id}/items`} method="post" className="form-stack">
              <div className="form-row">
                <label>SKU *
                  <select name="product_variant_id" required>
                    <option value="">Chọn SKU</option>
                    {allVariants.map((v)=><option key={v.id} value={v.id}>{v.sku_code} · {productsById.get(v.product_id)?.name??v.variant_name??""}</option>)}
                  </select>
                </label>
                <label>Packaging
                  <select name="packaging_id">
                    <option value="">Custom purchase unit</option>
                    {packaging.map((p)=><option key={p.id} value={p.id}>{variantsById.get(p.product_variant_id)?.sku_code??"SKU"} · {p.package_name} ({num(p.units_per_package)})</option>)}
                  </select>
                </label>
              </div>
              <div className="form-row">
                <label>Purchase unit *<input name="purchase_unit" placeholder="carton, box..." /></label>
                <label>Units / purchase unit *<input type="number" step="any" min="0.000001" name="units_per_purchase_unit" /></label>
              </div>
              <div className="form-row">
                <label>Package quantity *<input type="number" step="any" min="0.000001" name="package_quantity" required /></label>
                <label>Unit cost / purchase unit *<input type="number" step="any" min="0" name="unit_cost_per_purchase_unit" required /></label>
              </div>
              <label>Notes<textarea name="notes" rows={2} /></label>
              <button className="button button-primary" type="submit">Thêm line</button>
            </form>

            {items.map((item)=>{
              const variant=variantsById.get(item.product_variant_id);
              return(
                <form action={`/api/purchases/items/${item.id}`} method="post" className="form-stack package-editor" key={`edit-${item.id}`}>
                  <input type="hidden" name="purchase_order_id" value={order.id} />
                  <h3>Sửa {variant?.sku_code??"line item"}</h3>
                  <div className="form-row">
                    <label>SKU
                      <select name="product_variant_id" defaultValue={item.product_variant_id} required>
                        {allVariants.map((v)=><option key={v.id} value={v.id}>{v.sku_code}</option>)}
                      </select>
                    </label>
                    <label>Packaging
                      <select name="packaging_id" defaultValue={item.packaging_id??""}>
                        <option value="">Custom purchase unit</option>
                        {packaging.map((p)=><option key={p.id} value={p.id}>{variantsById.get(p.product_variant_id)?.sku_code??"SKU"} · {p.package_name}</option>)}
                      </select>
                    </label>
                  </div>
                  <div className="form-row">
                    <label>Purchase unit<input name="purchase_unit" defaultValue={item.purchase_unit} required /></label>
                    <label>Units / purchase unit<input type="number" step="any" min="0.000001" name="units_per_purchase_unit" defaultValue={item.units_per_purchase_unit} required /></label>
                  </div>
                  <div className="form-row">
                    <label>Package quantity<input type="number" step="any" min="0.000001" name="package_quantity" defaultValue={item.package_quantity} required /></label>
                    <label>Unit cost<input type="number" step="any" min="0" name="unit_cost_per_purchase_unit" defaultValue={item.unit_cost_per_purchase_unit} required /></label>
                  </div>
                  <label>Notes<textarea name="notes" rows={2} defaultValue={item.notes??""} /></label>
                  <button className="button button-secondary" type="submit">Lưu line</button>
                </form>
              );
            })}
          </>
        ):null}
      </section>

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>Payment history</h2>
          <div className="stack-list">
            {payments.map((payment)=>(
              <div className="stack-item" key={payment.id}>
                <div>
                  <strong>{money(payment.amount,order.currency_code)}</strong>
                  <div className="subtle">{payment.payment_date} · {payment.payment_method??"No method"}</div>
                  <div className="subtle">{payment.reference??payment.notes??"—"}</div>
                </div>
                <div className="align-right">
                  {payment.evidence_attachment_id
                    ? <a className="text-link" href={`/api/purchases/attachments/${payment.evidence_attachment_id}`}>Payment evidence</a>
                    : isOwner
                      ? <form action={`/api/purchases/${order.id}/attachments`} method="post" encType="multipart/form-data" className="form-stack">
                          <input type="hidden" name="attachment_kind" value="PAYMENT_EVIDENCE" />
                          <input type="hidden" name="purchase_payment_id" value={payment.id} />
                          <input type="file" name="file" required />
                          <button className="button button-secondary" type="submit">Upload evidence</button>
                        </form>
                      : "No evidence"}
                </div>
              </div>
            ))}
            {payments.length===0?<p className="empty-state">Chưa có supplier payment.</p>:null}
          </div>
        </article>

        <article className="content-card">
          <h2>PO documents</h2>
          <div className="stack-list">
            {attachments.map((attachment)=>(
              <div className="stack-item" key={attachment.id}>
                <div>
                  <strong>{attachment.original_file_name}</strong>
                  <div className="subtle">{attachment.attachment_kind} · {attachment.size_bytes??0} bytes</div>
                </div>
                <a className="text-link" href={`/api/purchases/attachments/${attachment.id}`}>Tải xuống</a>
              </div>
            ))}
            {attachments.length===0?<p className="empty-state">Chưa có attachment.</p>:null}
          </div>
          {isOwner?(
            <form action={`/api/purchases/${order.id}/attachments`} method="post" encType="multipart/form-data" className="form-stack">
              <input type="hidden" name="attachment_kind" value="DOCUMENT" />
              <label>Thêm PO document<input type="file" name="file" required /></label>
              <button className="button button-secondary" type="submit">Upload document</button>
            </form>
          ):null}
        </article>
      </section>

      <section className="content-card">
        <h2>Workflow boundary</h2>
        <p className="muted">
          OPS-020 dừng ở purchase order và supplier payment. Actual receipt date, goods receipt records,
          cost posting from received goods và inventory increase thuộc OPS-021/OPS-022; màn hình này không ghi các nghiệp vụ đó.
        </p>
      </section>
    </main>
  );
}

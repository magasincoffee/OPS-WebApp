import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Supplier = {
  id: string;
  supplier_name: string;
  is_active: boolean;
};

type PurchaseOrder = {
  id: string;
  po_number: string;
  supplier_id: string;
  status: string;
  order_date: string;
  expected_receipt_date: string | null;
  actual_receipt_date: string | null;
  freight_amount: number;
  currency_code: string;
  responsible_user_id: string | null;
};

type PurchaseOrderItem = {
  purchase_order_id: string;
  line_subtotal: number;
};

type PurchasePayment = {
  purchase_order_id: string;
  amount: number;
};

type User = {
  id: string;
  display_name: string | null;
  is_active: boolean;
};

type PageProps = {
  searchParams: Promise<{ q?: string; error?: string; created?: string }>;
};

function money(value: number, currency: string) {
  try {
    return new Intl.NumberFormat("vi-VN", {
      style: "currency",
      currency,
      maximumFractionDigits: currency === "VND" ? 0 : 2,
    }).format(Number(value));
  } catch {
    return `${Number(value).toLocaleString("vi-VN")} ${currency}`;
  }
}

export default async function PurchasesPage({ searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const isOwner = roles.has("OWNER_ADMIN");
  const canView = isOwner || roles.has("ACCOUNTING");
  const state = await searchParams;

  if (!canView) {
    return (
      <main className="app-shell">
        <header className="topbar">
          <div>
            <p className="eyebrow">OPS-WEBAPP · OPS-020</p>
            <h1>Purchase Orders</h1>
          </div>
          <Link href="/" className="button button-secondary">Trang chủ</Link>
        </header>
        <section className="content-card">
          <p className="permission-note">
            Purchase orders chứa cost và payment data nên chỉ OWNER/ADMIN và ACCOUNTING được xem.
            WAREHOUSE thao tác goods receipt ở workflow riêng.
          </p>
        </section>
      </main>
    );
  }

  let suppliers: Supplier[];
  let orders: PurchaseOrder[];
  let items: PurchaseOrderItem[];
  let payments: PurchasePayment[];
  let users: User[] = [];

  try {
    [suppliers, orders, items, payments] = await Promise.all([
      supabaseRest<Supplier[]>(
        "suppliers?select=id,supplier_name,is_active&order=supplier_name.asc&limit=1000",
      ),
      supabaseRest<PurchaseOrder[]>(
        "purchase_orders?select=id,po_number,supplier_id,status,order_date,expected_receipt_date,actual_receipt_date,freight_amount,currency_code,responsible_user_id&order=order_date.desc,created_at.desc&limit=1000",
      ),
      supabaseRest<PurchaseOrderItem[]>(
        "purchase_order_items?select=purchase_order_id,line_subtotal&limit=10000",
      ),
      supabaseRest<PurchasePayment[]>(
        "purchase_payments?select=purchase_order_id,amount&limit=10000",
      ),
    ]);
    if (isOwner) {
      users = await supabaseRest<User[]>(
        "users?select=id,display_name,is_active&is_active=eq.true&order=display_name.asc&limit=500",
      );
    }
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const suppliersById = new Map(suppliers.map((row) => [row.id, row]));
  const itemTotals = new Map<string, number>();
  for (const item of items) {
    itemTotals.set(item.purchase_order_id, (itemTotals.get(item.purchase_order_id) ?? 0) + Number(item.line_subtotal));
  }
  const paymentTotals = new Map<string, number>();
  for (const payment of payments) {
    paymentTotals.set(payment.purchase_order_id, (paymentTotals.get(payment.purchase_order_id) ?? 0) + Number(payment.amount));
  }

  const q=(state.q ?? "").trim().toLocaleLowerCase("vi");
  const visible=q
    ? orders.filter((order) => {
        const supplier=suppliersById.get(order.supplier_id);
        return [order.po_number,order.status,supplier?.supplier_name]
          .filter(Boolean).join(" ").toLocaleLowerCase("vi").includes(q);
      })
    : orders;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-020</p>
          <h1>Purchase Orders</h1>
          <p className="muted">
            Purchase requirement → PO → supplier payment → goods receipt. Goods receipt được xử lý ở OPS-021.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/suppliers" className="button button-secondary">Nhà cung cấp</Link>
          <Link href="/costing" className="button button-secondary">Giá vốn</Link>
          <form action="/api/auth/logout" method="post">
            <button type="submit" className="button button-secondary">Đăng xuất</button>
          </form>
        </div>
      </header>

      {state.created ? <div className="alert alert-success">Đã tạo purchase order.</div> : null}
      {state.error ? <div className="alert alert-error">Không thể lưu purchase order. Kiểm tra dữ liệu hoặc quyền.</div> : null}

      <section className="metric-grid">
        <article className="metric-card"><span>Tổng PO</span><strong>{orders.length}</strong></article>
        <article className="metric-card"><span>DRAFT</span><strong>{orders.filter((o)=>o.status==="DRAFT").length}</strong></article>
        <article className="metric-card"><span>ORDERED</span><strong>{orders.filter((o)=>o.status==="ORDERED").length}</strong></article>
        <article className="metric-card"><span>Chưa thanh toán đủ</span><strong>{orders.filter((o)=>(paymentTotals.get(o.id)??0)<((itemTotals.get(o.id)??0)+Number(o.freight_amount))).length}</strong></article>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Danh sách PO</h2>
            <p className="muted">{visible.length} purchase order hiển thị</p>
          </div>
          <form method="get" className="search-form">
            <input name="q" defaultValue={state.q ?? ""} placeholder="Tìm PO, supplier, status..." />
            <button type="submit" className="button button-secondary">Tìm</button>
          </form>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>PO</th><th>Supplier</th><th>Status</th><th>Order date</th><th>Expected</th><th>Total</th><th>Paid</th><th>Payment</th></tr>
            </thead>
            <tbody>
              {visible.map((order) => {
                const total=(itemTotals.get(order.id)??0)+Number(order.freight_amount);
                const paid=paymentTotals.get(order.id)??0;
                const paymentState=total>0 && paid>=total-0.000001 ? "PAID" : paid>0 ? "PARTIAL" : "UNPAID";
                return (
                  <tr key={order.id}>
                    <td><Link href={`/purchases/${order.id}`} className="row-link">{order.po_number}</Link></td>
                    <td>{suppliersById.get(order.supplier_id)?.supplier_name ?? "—"}</td>
                    <td><span className={order.status==="CANCELLED" ? "status status-muted" : "status status-active"}>{order.status}</span></td>
                    <td>{order.order_date}</td>
                    <td>{order.expected_receipt_date ?? "—"}</td>
                    <td>{money(total,order.currency_code)}</td>
                    <td>{money(paid,order.currency_code)}</td>
                    <td>{paymentState}</td>
                  </tr>
                );
              })}
              {visible.length===0 ? <tr><td colSpan={8} className="empty-state">Chưa có purchase order.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      {isOwner ? (
        <section className="content-card">
          <h2>Tạo purchase order</h2>
          <form action="/api/purchases" method="post" className="form-stack">
            <div className="form-row">
              <label>PO number *<input name="po_number" required /></label>
              <label>Supplier *
                <select name="supplier_id" required>
                  <option value="">Chọn supplier</option>
                  {suppliers.filter((s)=>s.is_active).map((s)=><option key={s.id} value={s.id}>{s.supplier_name}</option>)}
                </select>
              </label>
            </div>
            <div className="form-row">
              <label>Order date *<input type="date" name="order_date" defaultValue={new Date().toISOString().slice(0,10)} required /></label>
              <label>Expected receipt<input type="date" name="expected_receipt_date" /></label>
            </div>
            <div className="form-row">
              <label>Freight/logistics<input type="number" step="any" min="0" name="freight_amount" defaultValue="0" /></label>
              <label>Currency<input name="currency_code" defaultValue="VND" pattern="[A-Za-z]{3}" required /></label>
            </div>
            <div className="form-row">
              <label>Responsible user
                <select name="responsible_user_id">
                  <option value="">Chưa phân công</option>
                  {users.map((u)=><option key={u.id} value={u.id}>{u.display_name ?? u.id}</option>)}
                </select>
              </label>
              <label>Document reference<input name="document_reference" placeholder="PO/invoice/reference..." /></label>
            </div>
            <label>Payment note<textarea name="payment_note" rows={2} /></label>
            <label>Notes<textarea name="notes" rows={2} /></label>
            <button type="submit" className="button button-primary">Tạo PO</button>
          </form>
        </section>
      ) : null}
    </main>
  );
}

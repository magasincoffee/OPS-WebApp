import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Receipt = {
  id: string;
  goods_receipt_number: string;
  purchase_order_id: string;
  received_at: string;
  received_by_user_id: string | null;
  document_reference: string | null;
};

type ReceiptItem = {
  goods_receipt_id: string;
  package_quantity: number;
  base_quantity: number;
};

type SourceLine = {
  purchase_order_id: string;
  po_number: string;
  supplier_name: string;
  po_status: string;
  order_date: string;
  expected_receipt_date: string | null;
  payment_ready: boolean;
  remaining_package_quantity: number;
};

type PageProps = {
  searchParams: Promise<{ q?: string; created?: string; error?: string }>;
};

function dateTime(value: string) {
  return new Intl.DateTimeFormat("vi-VN", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function num(value: number) {
  return new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 6 }).format(Number(value));
}

export default async function ReceiptsPage({ searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const isOwner = roles.has("OWNER_ADMIN");
  const isWarehouse = roles.has("WAREHOUSE");
  const isAccounting = roles.has("ACCOUNTING");
  const canView = isOwner || isWarehouse || isAccounting;
  const canReceive = isOwner || isWarehouse;
  const state = await searchParams;

  if (!canView) {
    return (
      <main className="app-shell">
        <header className="topbar">
          <div>
            <p className="eyebrow">OPS-WEBAPP · OPS-021</p>
            <h1>Goods Receipts</h1>
          </div>
          <Link href="/" className="button button-secondary">Trang chủ</Link>
        </header>
        <section className="content-card">
          <p className="permission-note">
            Goods receipt dành cho OWNER/ADMIN, WAREHOUSE và ACCOUNTING read-only.
          </p>
        </section>
      </main>
    );
  }

  let receipts: Receipt[];
  let receiptItems: ReceiptItem[];
  let sourceLines: SourceLine[];

  try {
    [receipts, receiptItems, sourceLines] = await Promise.all([
      supabaseRest<Receipt[]>(
        "goods_receipts?select=id,goods_receipt_number,purchase_order_id,received_at,received_by_user_id,document_reference&order=received_at.desc&limit=1000",
      ),
      supabaseRest<ReceiptItem[]>(
        "goods_receipt_items?select=goods_receipt_id,package_quantity,base_quantity&limit=10000",
      ),
      supabaseRest<SourceLine[]>(
        "goods_receipt_source_lines?select=purchase_order_id,po_number,supplier_name,po_status,order_date,expected_receipt_date,payment_ready,remaining_package_quantity&order=order_date.desc,po_number.desc&limit=10000",
      ),
    ]);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const sourceByPo = new Map<string, SourceLine>();
  for (const row of sourceLines) {
    if (!sourceByPo.has(row.purchase_order_id)) sourceByPo.set(row.purchase_order_id, row);
  }

  const receiptTotals = new Map<string, { packages: number; base: number }>();
  for (const item of receiptItems) {
    const current = receiptTotals.get(item.goods_receipt_id) ?? { packages: 0, base: 0 };
    current.packages += Number(item.package_quantity);
    current.base += Number(item.base_quantity);
    receiptTotals.set(item.goods_receipt_id, current);
  }

  const q = (state.q ?? "").trim().toLocaleLowerCase("vi");
  const visible = q
    ? receipts.filter((receipt) => {
        const source = sourceByPo.get(receipt.purchase_order_id);
        return [receipt.goods_receipt_number, source?.po_number, source?.supplier_name]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase("vi")
          .includes(q);
      })
    : receipts;

  const createablePo = [...sourceByPo.values()].filter((po) =>
    po.payment_ready &&
    po.po_status !== "CANCELLED" &&
    sourceLines.some(
      (line) =>
        line.purchase_order_id === po.purchase_order_id &&
        Number(line.remaining_package_quantity) > 0,
    ),
  );

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-021</p>
          <h1>Goods Receipts</h1>
          <p className="muted">
            Nhận hàng theo PO mà không lộ unit cost cho WAREHOUSE. Inventory posting thuộc OPS-022.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/purchases" className="button button-secondary">Purchase Orders</Link>
          <Link href="/products" className="button button-secondary">Sản phẩm &amp; SKU</Link>
          <form action="/api/auth/logout" method="post">
            <button type="submit" className="button button-secondary">Đăng xuất</button>
          </form>
        </div>
      </header>

      {state.created ? <div className="alert alert-success">Đã tạo goods receipt.</div> : null}
      {state.error ? (
        <div className="alert alert-error">
          {state.error === "payment"
            ? "PO chưa hoàn tất supplier payment nên chưa thể nhận hàng."
            : state.error === "cancelled"
              ? "PO đã CANCELLED."
              : "Không thể lưu goods receipt. Kiểm tra dữ liệu, PO source hoặc quyền."}
        </div>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card"><span>Receipts</span><strong>{receipts.length}</strong></article>
        <article className="metric-card"><span>PO đã nhận</span><strong>{new Set(receipts.map((r) => r.purchase_order_id)).size}</strong></article>
        <article className="metric-card"><span>Receipt lines</span><strong>{receiptItems.length}</strong></article>
        <article className="metric-card"><span>Base units received</span><strong className="metric-small">{num(receiptItems.reduce((sum, i) => sum + Number(i.base_quantity), 0))}</strong></article>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Lịch sử nhận hàng</h2>
            <p className="muted">{visible.length} receipt hiển thị</p>
          </div>
          <form method="get" className="search-form">
            <input name="q" defaultValue={state.q ?? ""} placeholder="Tìm GR, PO, supplier..." />
            <button type="submit" className="button button-secondary">Tìm</button>
          </form>
        </div>
        <div className="table-wrap">
          <table>
            <thead><tr><th>GR</th><th>PO</th><th>Supplier</th><th>Received at</th><th>Packages</th><th>Base units</th><th>Document</th></tr></thead>
            <tbody>
              {visible.map((receipt) => {
                const source = sourceByPo.get(receipt.purchase_order_id);
                const totals = receiptTotals.get(receipt.id) ?? { packages: 0, base: 0 };
                return (
                  <tr key={receipt.id}>
                    <td><Link href={`/receipts/${receipt.id}`} className="row-link">{receipt.goods_receipt_number}</Link></td>
                    <td>{source?.po_number ?? receipt.purchase_order_id}</td>
                    <td>{source?.supplier_name ?? "—"}</td>
                    <td>{dateTime(receipt.received_at)}</td>
                    <td>{num(totals.packages)}</td>
                    <td>{num(totals.base)}</td>
                    <td>{receipt.document_reference ?? "—"}</td>
                  </tr>
                );
              })}
              {visible.length === 0 ? <tr><td colSpan={7} className="empty-state">Chưa có goods receipt.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      {canReceive ? (
        <section className="content-card">
          <h2>Tạo goods receipt</h2>
          <p className="muted">
            Chỉ PO đã ghi nhận đủ supplier payment và còn quantity chưa nhận mới xuất hiện.
          </p>
          <form action="/api/receipts" method="post" className="form-stack">
            <div className="form-row">
              <label>Goods receipt number *<input name="goods_receipt_number" required /></label>
              <label>Purchase order *
                <select name="purchase_order_id" required>
                  <option value="">Chọn PO</option>
                  {createablePo.map((po) => (
                    <option key={po.purchase_order_id} value={po.purchase_order_id}>
                      {po.po_number} · {po.supplier_name} · expected {po.expected_receipt_date ?? "—"}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <label>Document reference<input name="document_reference" placeholder="Delivery note, packing list..." /></label>
            <label>Notes<textarea name="notes" rows={2} /></label>
            <button type="submit" className="button button-primary">Tạo receipt</button>
          </form>
        </section>
      ) : null}
    </main>
  );
}

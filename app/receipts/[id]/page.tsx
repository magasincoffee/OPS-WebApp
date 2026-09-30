import Link from "next/link";
import { notFound, redirect } from "next/navigation";
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
  notes: string | null;
};

type ReceiptItem = {
  id: string;
  goods_receipt_id: string;
  purchase_order_item_id: string;
  package_quantity: number;
  units_per_purchase_unit: number;
  base_quantity: number;
  notes: string | null;
};

type SourceLine = {
  purchase_order_id: string;
  po_number: string;
  supplier_name: string;
  po_status: string;
  payment_ready: boolean;
  purchase_order_item_id: string;
  product_variant_id: string;
  sku_code: string;
  variant_name: string | null;
  product_name: string;
  package_name: string | null;
  purchase_unit: string;
  ordered_package_quantity: number;
  units_per_purchase_unit: number;
  ordered_base_quantity: number;
  received_package_quantity: number;
  remaining_package_quantity: number;
  received_base_quantity: number;
  remaining_base_quantity: number;
};

type Attachment = {
  id: string;
  original_file_name: string;
  media_type: string | null;
  size_bytes: number | null;
  created_at: string;
};

type InventoryMovement = {
  id: string;
  goods_receipt_item_id: string | null;
  occurred_at: string;
};

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{
    created?: string;
    saved?: string;
    item_saved?: string;
    attachment_saved?: string;
    error?: string;
  }>;
};

function num(value: number) {
  return new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 6 }).format(Number(value));
}

function dateTime(value: string) {
  return new Intl.DateTimeFormat("vi-VN", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function ReceiptDetailPage({ params, searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const isOwner = roles.has("OWNER_ADMIN");
  const isWarehouse = roles.has("WAREHOUSE");
  const isAccounting = roles.has("ACCOUNTING");
  const canReceive = isOwner || isWarehouse;
  const canView = canReceive || isAccounting;
  if (!canView) redirect("/receipts");

  const { id } = await params;
  const state = await searchParams;
  const encoded = encodeURIComponent(id);

  let receiptRows: Receipt[];
  try {
    receiptRows = await supabaseRest<Receipt[]>(
      `goods_receipts?id=eq.${encoded}&select=id,goods_receipt_number,purchase_order_id,received_at,received_by_user_id,document_reference,notes`,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const receipt = receiptRows[0];
  if (!receipt) notFound();

  const [items, sourceLines, attachments] = await Promise.all([
    supabaseRest<ReceiptItem[]>(
      `goods_receipt_items?goods_receipt_id=eq.${encoded}&select=id,goods_receipt_id,purchase_order_item_id,package_quantity,units_per_purchase_unit,base_quantity,notes&order=created_at.asc&limit=1000`,
    ),
    supabaseRest<SourceLine[]>(
      `goods_receipt_source_lines?purchase_order_id=eq.${encodeURIComponent(receipt.purchase_order_id)}&select=purchase_order_id,po_number,supplier_name,po_status,payment_ready,purchase_order_item_id,product_variant_id,sku_code,variant_name,product_name,package_name,purchase_unit,ordered_package_quantity,units_per_purchase_unit,ordered_base_quantity,received_package_quantity,remaining_package_quantity,received_base_quantity,remaining_base_quantity&order=sku_code.asc&limit=1000`,
    ),
    supabaseRest<Attachment[]>(
      `attachments?linked_entity_type=eq.GOODS_RECEIPT&linked_entity_id=eq.${encoded}&select=id,original_file_name,media_type,size_bytes,created_at&order=created_at.desc&limit=500`,
    ),
  ]);

  const postedMovements = canReceive && items.length > 0
    ? await supabaseRest<InventoryMovement[]>(
        `inventory_movements?movement_type=eq.GOODS_RECEIPT&goods_receipt_item_id=in.(${items.map((item) => item.id).join(",")})&select=id,goods_receipt_item_id,occurred_at&limit=1000`,
      )
    : [];

  const postedItemIds = new Set(
    postedMovements
      .map((movement) => movement.goods_receipt_item_id)
      .filter((value): value is string => Boolean(value)),
  );
  const sourceByItem = new Map(sourceLines.map((line) => [line.purchase_order_item_id, line]));
  const po = sourceLines[0];
  const totalBase = items.reduce((sum, item) => sum + Number(item.base_quantity), 0);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <Link href="/receipts" className="text-link">← Goods Receipts</Link>
          <p className="eyebrow">GOODS RECEIPT</p>
          <h1>{receipt.goods_receipt_number}</h1>
          <p className="muted">
            {po?.po_number ?? receipt.purchase_order_id} · {po?.supplier_name ?? "Supplier"} · {dateTime(receipt.received_at)}
          </p>
        </div>
        <form action="/api/auth/logout" method="post">
          <button type="submit" className="button button-secondary">Đăng xuất</button>
        </form>
      </header>

      {state.created || state.saved || state.item_saved || state.attachment_saved ? (
        <div className="alert alert-success">Đã lưu goods receipt.</div>
      ) : null}
      {state.error ? (
        <div className="alert alert-error">
          Không thể lưu receipt. Kiểm tra PO source, package quantity, conversion hoặc quyền.
        </div>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card"><span>Receipt lines</span><strong>{items.length}</strong></article>
        <article className="metric-card"><span>Base units received</span><strong className="metric-small">{num(totalBase)}</strong></article>
        <article className="metric-card"><span>PO payment ready</span><strong>{po?.payment_ready ? "YES" : "NO"}</strong></article>
        <article className="metric-card"><span>Inventory posted</span><strong>{canReceive ? `${postedItemIds.size}/${items.length}` : "Restricted"}</strong></article>
      </section>

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>Receipt header</h2>
          <div className="stack-list">
            <div className="stack-item"><span>PO</span><strong>{po?.po_number ?? receipt.purchase_order_id}</strong></div>
            <div className="stack-item"><span>Supplier</span><strong>{po?.supplier_name ?? "—"}</strong></div>
            <div className="stack-item"><span>Received at</span><strong>{dateTime(receipt.received_at)}</strong></div>
            <div className="stack-item"><span>Received by</span><strong>{receipt.received_by_user_id ?? "—"}</strong></div>
          </div>
          {canReceive ? (
            <form action={`/api/receipts/${receipt.id}`} method="post" className="form-stack">
              <label>Document reference<input name="document_reference" defaultValue={receipt.document_reference ?? ""} /></label>
              <label>Notes<textarea name="notes" rows={3} defaultValue={receipt.notes ?? ""} /></label>
              <button type="submit" className="button button-secondary">Lưu receipt</button>
            </form>
          ) : (
            <p className="muted">{receipt.notes ?? "Không có ghi chú."}</p>
          )}
        </article>

        <aside className="content-card">
          <h2>PO receiving progress</h2>
          <div className="stack-list">
            {sourceLines.map((line) => (
              <div className="stack-item" key={line.purchase_order_item_id}>
                <div>
                  <strong>{line.sku_code}</strong>
                  <div className="subtle">{line.product_name}{line.variant_name ? ` · ${line.variant_name}` : ""}</div>
                </div>
                <div className="align-right">
                  <strong>{num(line.received_package_quantity)} / {num(line.ordered_package_quantity)} {line.purchase_unit}</strong>
                  <div className="subtle">remaining {num(line.remaining_base_quantity)} base units</div>
                </div>
              </div>
            ))}
          </div>
        </aside>
      </section>

      <section className="content-card">
        <h2>Received lines</h2>
        <div className="table-wrap">
          <table>
            <thead><tr><th>SKU</th><th>Product</th><th>Purchase unit</th><th>Package qty</th><th>Conversion</th><th>Base qty</th><th>Notes</th><th>Inventory</th></tr></thead>
            <tbody>
              {items.map((item) => {
                const source = sourceByItem.get(item.purchase_order_item_id);
                return (
                  <tr key={item.id}>
                    <td>{source?.sku_code ?? item.purchase_order_item_id}</td>
                    <td>{source?.product_name ?? "—"}</td>
                    <td>{source?.package_name ?? source?.purchase_unit ?? "—"}</td>
                    <td>{num(item.package_quantity)}</td>
                    <td>1 {source?.purchase_unit ?? "unit"} = {num(item.units_per_purchase_unit)} base units</td>
                    <td>{num(item.base_quantity)}</td>
                    <td>{item.notes ?? "—"}</td>
                    <td>
                      {canReceive ? (
                        postedItemIds.has(item.id) ? (
                          <span className="status status-active">POSTED</span>
                        ) : (
                          <form action={`/api/inventory/receipts/${item.id}/post`} method="post">
                            <input type="hidden" name="goods_receipt_id" value={receipt.id} />
                            <button type="submit" className="button button-secondary">Post inventory</button>
                          </form>
                        )
                      ) : "—"}
                    </td>
                  </tr>
                );
              })}
              {items.length === 0 ? <tr><td colSpan={8} className="empty-state">Chưa ghi nhận received line.</td></tr> : null}
            </tbody>
          </table>
        </div>

        {canReceive ? (
          <>
            <h3>Thêm received line</h3>
            <form action={`/api/receipts/${receipt.id}/items`} method="post" className="form-stack">
              <label>PO line *
                <select name="purchase_order_item_id" required>
                  <option value="">Chọn PO line</option>
                  {sourceLines.filter((line) => Number(line.remaining_package_quantity) > 0).map((line) => (
                    <option key={line.purchase_order_item_id} value={line.purchase_order_item_id}>
                      {line.sku_code} · {line.product_name} · remaining {num(line.remaining_package_quantity)} {line.purchase_unit}
                    </option>
                  ))}
                </select>
              </label>
              <div className="form-row">
                <label>Received package quantity *<input type="number" step="any" min="0.000001" name="package_quantity" required /></label>
                <label>Notes<input name="notes" /></label>
              </div>
              <button type="submit" className="button button-primary">Ghi nhận line</button>
            </form>

            {items.filter((item) => !postedItemIds.has(item.id)).map((item) => {
              const source = sourceByItem.get(item.purchase_order_item_id);
              return (
                <form action={`/api/receipts/items/${item.id}`} method="post" className="form-stack package-editor" key={`edit-${item.id}`}>
                  <input type="hidden" name="goods_receipt_id" value={receipt.id} />
                  <input type="hidden" name="purchase_order_item_id" value={item.purchase_order_item_id} />
                  <h3>Sửa {source?.sku_code ?? "received line"}</h3>
                  <div className="form-row">
                    <label>Package quantity<input type="number" step="any" min="0.000001" name="package_quantity" defaultValue={item.package_quantity} required /></label>
                    <label>Notes<input name="notes" defaultValue={item.notes ?? ""} /></label>
                  </div>
                  <button type="submit" className="button button-secondary">Lưu line</button>
                </form>
              );
            })}
          </>
        ) : null}
      </section>

      <section className="content-card">
        <h2>Receipt documents</h2>
        <div className="stack-list">
          {attachments.map((attachment) => (
            <div className="stack-item" key={attachment.id}>
              <div>
                <strong>{attachment.original_file_name}</strong>
                <div className="subtle">{attachment.media_type ?? "document"} · {attachment.size_bytes ?? 0} bytes</div>
              </div>
              <a className="text-link" href={`/api/receipts/attachments/${attachment.id}`}>Tải xuống</a>
            </div>
          ))}
          {attachments.length === 0 ? <p className="empty-state">Chưa có receipt document.</p> : null}
        </div>
        {canReceive ? (
          <form action={`/api/receipts/${receipt.id}/attachments`} method="post" encType="multipart/form-data" className="form-stack">
            <label>Thêm receipt document<input type="file" name="file" required /></label>
            <button type="submit" className="button button-secondary">Upload document</button>
          </form>
        ) : null}
      </section>

      <section className="content-card">
        <h2>Workflow boundary</h2>
        <p className="muted">
          OPS-022 post từng received line đúng một lần vào immutable inventory ledger; stock snapshot được dẫn xuất từ ledger và cost history được append tự động.
          Reservation/release/issue thuộc OPS-023; stocktake/adjustment/low-stock thuộc OPS-024.
        </p>
      </section>
    </main>
  );
}

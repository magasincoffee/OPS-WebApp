import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Product = { id: string; name: string };
type Variant = {
  id: string;
  product_id: string;
  sku_code: string;
  variant_name: string | null;
  base_inventory_unit: string;
  minimum_stock_quantity: number;
  is_active: boolean;
};
type Stock = {
  product_variant_id: string;
  on_hand_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
};
type Movement = {
  id: string;
  product_variant_id: string;
  movement_type: string;
  quantity_delta_base_units: number;
  goods_receipt_item_id: string | null;
  inventory_reservation_id: string | null;
  sales_order_item_id: string | null;
  reference: string | null;
  reason: string | null;
  created_by_user_id: string | null;
  occurred_at: string;
};
type LowStock = {
  product_variant_id: string;
  sku_code: string;
  variant_name: string | null;
  product_name: string;
  base_inventory_unit: string;
  minimum_stock_quantity: number;
  on_hand_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
  shortage_quantity: number;
};
type Stocktake = {
  id: string;
  stocktake_number: string;
  stocktake_date: string;
  status: string;
  counted_at: string | null;
  posted_at: string | null;
  notes: string | null;
};
type StocktakeItem = {
  id: string;
  stocktake_id: string;
  product_variant_id: string;
  system_on_hand_quantity: number;
  counted_on_hand_quantity: number | null;
  variance_quantity: number | null;
  notes: string | null;
};
type ReservationQueueRow = {
  sales_order_item_id: string;
  sales_order_id: string;
  inventory_reservation_id: string | null;
  order_number: string;
  order_status: string;
  warehouse_status: string;
  requested_due_date: string | null;
  product_variant_id: string;
  sku_code: string;
  variant_name: string | null;
  product_name: string;
  base_inventory_unit: string;
  base_quantity: number;
  issued_quantity: number;
  reserved_balance_quantity: number;
  outstanding_quantity: number;
  available_quantity: number;
};

type PageProps = {
  searchParams: Promise<{
    q?: string;
    type?: string;
    reservation?: string;
    error?: string;
    action?: string;
    stocktake?: string;
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

function dateOnly(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("vi-VN", { dateStyle: "short" }).format(
    new Date(`${value}T00:00:00`),
  );
}

function workflowState(row: ReservationQueueRow) {
  if (Number(row.issued_quantity) >= Number(row.base_quantity)) return "ISSUED";
  if (Number(row.reserved_balance_quantity) > 0) return "RESERVED";
  if (row.order_status === "CANCELLED") return "CANCELLED";
  return "WAITING";
}

export default async function InventoryPage({ searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const canView = roles.has("OWNER_ADMIN") || roles.has("WAREHOUSE");
  const state = await searchParams;

  if (!canView) {
    return (
      <main className="app-shell">
        <header className="topbar">
          <div>
            <p className="eyebrow">OPS-WEBAPP · OPS-024</p>
            <h1>Inventory</h1>
          </div>
          <Link href="/" className="button button-secondary">Trang chủ</Link>
        </header>
        <section className="content-card">
          <p className="permission-note">
            Inventory reservation và ledger dành cho OWNER/ADMIN và WAREHOUSE.
          </p>
        </section>
      </main>
    );
  }

  let products: Product[];
  let variants: Variant[];
  let stock: Stock[];
  let movements: Movement[];
  let queue: ReservationQueueRow[];
  let lowStock: LowStock[];
  let stocktakes: Stocktake[];

  try {
    [products, variants, stock, movements, queue, lowStock, stocktakes] = await Promise.all([
      supabaseRest<Product[]>("products?select=id,name&order=name.asc&limit=2000"),
      supabaseRest<Variant[]>(
        "product_variants?select=id,product_id,sku_code,variant_name,base_inventory_unit,minimum_stock_quantity,is_active&order=sku_code.asc&limit=5000",
      ),
      supabaseRest<Stock[]>(
        "inventory_stock_snapshot?select=product_variant_id,on_hand_quantity,reserved_quantity,available_quantity&limit=5000",
      ),
      supabaseRest<Movement[]>(
        "inventory_movements?select=id,product_variant_id,movement_type,quantity_delta_base_units,goods_receipt_item_id,inventory_reservation_id,sales_order_item_id,reference,reason,created_by_user_id,occurred_at&order=occurred_at.desc,created_at.desc&limit=2000",
      ),
      supabaseRest<ReservationQueueRow[]>("rpc/inventory_reservation_work_queue", {
        method: "POST",
        body: "{}",
      }),
      supabaseRest<LowStock[]>(
        "inventory_low_stock?select=product_variant_id,sku_code,variant_name,product_name,base_inventory_unit,minimum_stock_quantity,on_hand_quantity,reserved_quantity,available_quantity,shortage_quantity&order=shortage_quantity.desc,sku_code.asc&limit=5000",
      ),
      supabaseRest<Stocktake[]>(
        "stocktakes?select=id,stocktake_number,stocktake_date,status,counted_at,posted_at,notes&order=stocktake_date.desc,created_at.desc&limit=100",
      ),
    ]);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const selectedStocktakeId =
    state.stocktake ?? stocktakes.find((row) => row.status !== "POSTED")?.id ?? stocktakes[0]?.id ?? null;
  let stocktakeItems: StocktakeItem[] = [];
  if (selectedStocktakeId) {
    stocktakeItems = await supabaseRest<StocktakeItem[]>(
      `stocktake_items?stocktake_id=eq.${encodeURIComponent(selectedStocktakeId)}&select=id,stocktake_id,product_variant_id,system_on_hand_quantity,counted_on_hand_quantity,variance_quantity,notes&order=created_at.asc&limit=5000`,
    );
  }
  const selectedStocktake = stocktakes.find((row) => row.id === selectedStocktakeId);
  const allStocktakeItemsCounted =
    stocktakeItems.length > 0 && stocktakeItems.every((row) => row.counted_on_hand_quantity !== null);

  const productById = new Map(products.map((row) => [row.id, row]));
  const variantById = new Map(variants.map((row) => [row.id, row]));
  const stockByVariant = new Map(stock.map((row) => [row.product_variant_id, row]));

  const q = (state.q ?? "").trim().toLocaleLowerCase("vi");
  const movementType = (state.type ?? "").trim();

  const visibleVariants = variants.filter((variant) => {
    if (!q) return true;
    const product = productById.get(variant.product_id);
    return [variant.sku_code, variant.variant_name, product?.name]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase("vi")
      .includes(q);
  });

  const visibleMovements = movements.filter((movement) => {
    if (movementType && movement.movement_type !== movementType) return false;
    if (!q) return true;
    const variant = variantById.get(movement.product_variant_id);
    const product = variant ? productById.get(variant.product_id) : undefined;
    return [
      movement.movement_type,
      movement.reference,
      movement.reason,
      variant?.sku_code,
      variant?.variant_name,
      product?.name,
    ]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase("vi")
      .includes(q);
  });

  const movementTypes = [...new Set(movements.map((row) => row.movement_type))].sort();
  const totalOnHand = stock.reduce((sum, row) => sum + Number(row.on_hand_quantity), 0);
  const totalReserved = stock.reduce((sum, row) => sum + Number(row.reserved_quantity), 0);
  const totalAvailable = stock.reduce((sum, row) => sum + Number(row.available_quantity), 0);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-024</p>
          <h1>Inventory</h1>
          <p className="muted">
            Reserve, release và issue theo sales-order line; stock truth vẫn chỉ đến từ immutable inventory movements.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/receipts" className="button button-secondary">Goods Receipts</Link>
          <Link href="/products" className="button button-secondary">Sản phẩm &amp; SKU</Link>
          <form action="/api/auth/logout" method="post">
            <button type="submit" className="button button-secondary">Đăng xuất</button>
          </form>
        </div>
      </header>

      {state.action ? (
        <section className="content-card">
          <p className="permission-note">Inventory action completed: {state.action}.</p>
        </section>
      ) : null}

      {state.reservation ? (
        <section className="content-card">
          <p className="permission-note">Inventory action completed: {state.reservation}.</p>
        </section>
      ) : null}

      {state.error ? (
        <section className="content-card">
          <p className="permission-note">
            Không thể hoàn tất inventory action ({state.error}). Kiểm tra số lượng, trạng thái đơn hàng và available stock.
          </p>
        </section>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card"><span>SKU tracked</span><strong>{variants.length}</strong></article>
        <article className="metric-card"><span>On hand</span><strong className="metric-small">{num(totalOnHand)}</strong></article>
        <article className="metric-card"><span>Reserved</span><strong className="metric-small">{num(totalReserved)}</strong></article>
        <article className="metric-card"><span>Available</span><strong className="metric-small">{num(totalAvailable)}</strong></article>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Reservation / release / issue queue</h2>
            <p className="muted">
              Queue chỉ chứa dữ liệu vận hành cần cho kho; không mở quyền đọc bảng sales hoặc selling-price data cho WAREHOUSE.
            </p>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Order</th><th>SKU</th><th>Due</th><th>Base qty</th><th>Issued</th>
                <th>Reserved</th><th>Outstanding</th><th>Available</th><th>State</th><th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {queue.map((row) => {
                const outstanding = Number(row.outstanding_quantity);
                const reserved = Number(row.reserved_balance_quantity);
                const available = Number(row.available_quantity);
                const reserveMax = Math.max(Math.min(outstanding, available), 0);
                const canReserve = row.order_status === "CONFIRMED" && reserveMax > 0;
                const canIssue = row.order_status === "CONFIRMED" && reserved > 0;
                return (
                  <tr key={row.sales_order_item_id}>
                    <td>
                      <strong>{row.order_number}</strong>
                      <div className="subtle">{row.order_status} · {row.warehouse_status}</div>
                    </td>
                    <td><strong>{row.sku_code}</strong><div className="subtle">{row.product_name}</div></td>
                    <td>{dateOnly(row.requested_due_date)}</td>
                    <td>{num(row.base_quantity)} {row.base_inventory_unit}</td>
                    <td>{num(row.issued_quantity)}</td>
                    <td>{num(reserved)}</td>
                    <td>{num(outstanding)}</td>
                    <td>{num(available)}</td>
                    <td>{workflowState(row)}</td>
                    <td>
                      <div className="form-stack">
                        {canReserve ? (
                          <form action="/api/inventory/reservations" method="post" className="search-form">
                            <input type="hidden" name="sales_order_item_id" value={row.sales_order_item_id} />
                            <input
                              type="number"
                              name="quantity"
                              min="0.000001"
                              max={reserveMax}
                              step="any"
                              defaultValue={reserveMax}
                              aria-label={`Reserve quantity for ${row.order_number} ${row.sku_code}`}
                            />
                            <button type="submit" className="button button-secondary">Reserve</button>
                          </form>
                        ) : null}
                        {row.inventory_reservation_id && reserved > 0 ? (
                          <>
                            <form
                              action={`/api/inventory/reservations/${row.inventory_reservation_id}/release`}
                              method="post"
                              className="search-form"
                            >
                              <input type="number" name="quantity" min="0.000001" max={reserved} step="any" defaultValue={reserved} aria-label="Release quantity" />
                              <button type="submit" className="button button-secondary">Release</button>
                            </form>
                            {canIssue ? (
                              <form
                                action={`/api/inventory/reservations/${row.inventory_reservation_id}/issue`}
                                method="post"
                                className="search-form"
                              >
                                <input type="number" name="quantity" min="0.000001" max={reserved} step="any" defaultValue={reserved} aria-label="Issue quantity" />
                                <button type="submit" className="button button-primary">Issue</button>
                              </form>
                            ) : null}
                          </>
                        ) : null}
                        {!canReserve && reserved <= 0 ? <span className="subtle">—</span> : null}
                      </div>
                    </td>
                  </tr>
                );
              })}
              {queue.length === 0 ? <tr><td colSpan={10} className="empty-state">Không có sales-order line cần xử lý kho.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>


      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Low-stock</h2>
            <p className="muted">Available quantity so với minimum stock đã cấu hình cho SKU.</p>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead><tr><th>SKU</th><th>Product</th><th>On hand</th><th>Reserved</th><th>Available</th><th>Minimum</th><th>Shortage</th></tr></thead>
            <tbody>
              {lowStock.map((row) => (
                <tr key={row.product_variant_id}>
                  <td><strong>{row.sku_code}</strong>{row.variant_name ? <div className="subtle">{row.variant_name}</div> : null}</td>
                  <td>{row.product_name}</td>
                  <td>{num(row.on_hand_quantity)}</td>
                  <td>{num(row.reserved_quantity)}</td>
                  <td>{num(row.available_quantity)}</td>
                  <td>{num(row.minimum_stock_quantity)}</td>
                  <td>{num(row.shortage_quantity)} {row.base_inventory_unit}</td>
                </tr>
              ))}
              {lowStock.length === 0 ? <tr><td colSpan={7} className="empty-state">Không có SKU dưới ngưỡng minimum stock.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="content-card">
        <h2>Manual adjustment</h2>
        <p className="muted">Số dương = ADJUSTMENT_IN, số âm = ADJUSTMENT_OUT. Reason bắt buộc.</p>
        <form action="/api/inventory/operations" method="post" className="form-stack">
          <input type="hidden" name="operation" value="adjust_inventory" />
          <label>SKU
            <select name="product_variant_id" required defaultValue="">
              <option value="" disabled>Chọn SKU</option>
              {variants.filter((row) => row.is_active).map((row) => (
                <option key={row.id} value={row.id}>{row.sku_code} · {row.variant_name ?? productById.get(row.product_id)?.name ?? ""}</option>
              ))}
            </select>
          </label>
          <label>Quantity delta<input type="number" name="quantity_delta" step="any" required placeholder="+10 hoặc -3" /></label>
          <label>Reason<input name="reason" required placeholder="Hàng hỏng, correction, tìm thấy hàng..." /></label>
          <button type="submit" className="button button-primary">Ghi adjustment</button>
        </form>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Stocktake</h2>
            <p className="muted">Snapshot on-hand từ ledger → đếm thực tế → COUNTED → post variance.</p>
          </div>
          <form action="/api/inventory/operations" method="post" className="search-form">
            <input type="hidden" name="operation" value="create_stocktake" />
            <input name="stocktake_number" required placeholder="ST-2026-09-30-01" />
            <input name="notes" placeholder="Ghi chú..." />
            <button type="submit" className="button button-primary">Tạo snapshot</button>
          </form>
        </div>

        <div className="hero-actions">
          {stocktakes.map((row) => (
            <Link
              key={row.id}
              href={`/inventory?stocktake=${row.id}`}
              className="button button-secondary"
            >
              {row.stocktake_number} · {row.status}
            </Link>
          ))}
        </div>

        {selectedStocktake ? (
          <>
            <div className="section-heading">
              <div>
                <h3>{selectedStocktake.stocktake_number} · {selectedStocktake.status}</h3>
                <p className="muted">
                  {stocktakeItems.length} SKU · {stocktakeItems.filter((row) => Number(row.variance_quantity ?? 0) !== 0).length} variance line(s)
                </p>
              </div>
              <div className="hero-actions">
                {selectedStocktake.status === "DRAFT" && allStocktakeItemsCounted ? (
                  <form action="/api/inventory/operations" method="post">
                    <input type="hidden" name="operation" value="finalize_stocktake" />
                    <input type="hidden" name="stocktake_id" value={selectedStocktake.id} />
                    <button type="submit" className="button button-primary">Chốt COUNTED</button>
                  </form>
                ) : null}
                {selectedStocktake.status === "COUNTED" ? (
                  <form action="/api/inventory/operations" method="post">
                    <input type="hidden" name="operation" value="post_stocktake" />
                    <input type="hidden" name="stocktake_id" value={selectedStocktake.id} />
                    <button type="submit" className="button button-primary">Post variance</button>
                  </form>
                ) : null}
              </div>
            </div>
            <div className="table-wrap">
              <table>
                <thead><tr><th>SKU</th><th>System</th><th>Counted</th><th>Variance</th><th>Action</th></tr></thead>
                <tbody>
                  {stocktakeItems.map((item) => {
                    const variant = variantById.get(item.product_variant_id);
                    return (
                      <tr key={item.id}>
                        <td><strong>{variant?.sku_code ?? item.product_variant_id}</strong></td>
                        <td>{num(item.system_on_hand_quantity)}</td>
                        <td>{item.counted_on_hand_quantity === null ? "—" : num(item.counted_on_hand_quantity)}</td>
                        <td>{item.variance_quantity === null ? "—" : num(item.variance_quantity)}</td>
                        <td>
                          {selectedStocktake.status === "DRAFT" ? (
                            <form action="/api/inventory/operations" method="post" className="search-form">
                              <input type="hidden" name="operation" value="count_stocktake" />
                              <input type="hidden" name="stocktake_id" value={selectedStocktake.id} />
                              <input type="hidden" name="stocktake_item_id" value={item.id} />
                              <input type="number" name="counted_quantity" min="0" step="any" required defaultValue={item.counted_on_hand_quantity ?? ""} />
                              <input name="notes" defaultValue={item.notes ?? ""} placeholder="Ghi chú..." />
                              <button type="submit" className="button button-secondary">Lưu đếm</button>
                            </form>
                          ) : item.notes ?? "—"}
                        </td>
                      </tr>
                    );
                  })}
                  {stocktakeItems.length === 0 ? <tr><td colSpan={5} className="empty-state">Không có SKU active trong snapshot.</td></tr> : null}
                </tbody>
              </table>
            </div>
            <p className="muted">
              Post bị chặn nếu ledger on-hand đã thay đổi sau snapshot, tránh ghi variance stale.
            </p>
          </>
        ) : <p className="empty-state">Chưa có stocktake.</p>}
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Stock snapshot</h2>
            <p className="muted">Không có editable stock balance. Mọi số lượng đến từ ledger.</p>
          </div>
          <form method="get" className="search-form">
            <input name="q" defaultValue={state.q ?? ""} placeholder="Tìm SKU hoặc sản phẩm..." />
            <button type="submit" className="button button-secondary">Tìm</button>
          </form>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>SKU</th><th>Sản phẩm</th><th>Base unit</th><th>On hand</th><th>Reserved</th><th>Available</th><th>Minimum stock</th><th>State</th></tr>
            </thead>
            <tbody>
              {visibleVariants.map((variant) => {
                const row = stockByVariant.get(variant.id);
                return (
                  <tr key={variant.id}>
                    <td><strong>{variant.sku_code}</strong>{variant.variant_name ? <div className="subtle">{variant.variant_name}</div> : null}</td>
                    <td>{productById.get(variant.product_id)?.name ?? "—"}</td>
                    <td>{variant.base_inventory_unit}</td>
                    <td>{num(Number(row?.on_hand_quantity ?? 0))}</td>
                    <td>{num(Number(row?.reserved_quantity ?? 0))}</td>
                    <td>{num(Number(row?.available_quantity ?? 0))}</td>
                    <td>{num(Number(variant.minimum_stock_quantity))}</td>
                    <td>{variant.is_active ? "ACTIVE" : "INACTIVE"}</td>
                  </tr>
                );
              })}
              {visibleVariants.length === 0 ? <tr><td colSpan={8} className="empty-state">Không có SKU phù hợp.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Movement history</h2>
            <p className="muted">Append-only; sửa/xóa movement hiện hữu bị database chặn.</p>
          </div>
          <form method="get" className="search-form">
            <input type="hidden" name="q" value={state.q ?? ""} />
            <select name="type" defaultValue={movementType}>
              <option value="">Tất cả movement</option>
              {movementTypes.map((type) => <option key={type} value={type}>{type}</option>)}
            </select>
            <button type="submit" className="button button-secondary">Lọc</button>
          </form>
        </div>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Time</th><th>SKU</th><th>Movement</th><th>Delta</th><th>Reference</th><th>Actor</th></tr></thead>
            <tbody>
              {visibleMovements.map((movement) => {
                const variant = variantById.get(movement.product_variant_id);
                return (
                  <tr key={movement.id}>
                    <td>{dateTime(movement.occurred_at)}</td>
                    <td>{variant?.sku_code ?? movement.product_variant_id}</td>
                    <td>{movement.movement_type}</td>
                    <td>{Number(movement.quantity_delta_base_units) > 0 ? "+" : ""}{num(movement.quantity_delta_base_units)} {variant?.base_inventory_unit ?? ""}</td>
                    <td>{movement.reference ?? movement.reason ?? "—"}</td>
                    <td>{movement.created_by_user_id ?? "SYSTEM"}</td>
                  </tr>
                );
              })}
              {visibleMovements.length === 0 ? <tr><td colSpan={6} className="empty-state">Chưa có movement phù hợp.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="content-card">
        <h2>Workflow boundary</h2>
        <p className="muted">
          OPS-024 bổ sung stocktake, reasoned manual adjustments và low-stock trên cùng immutable ledger.
          Quotation / sales-order authoring vẫn thuộc OPS-030 / OPS-031.
        </p>
      </section>
    </main>
  );
}

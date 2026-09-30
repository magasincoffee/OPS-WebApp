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

type PageProps = {
  searchParams: Promise<{ q?: string; type?: string }>;
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
            <p className="eyebrow">OPS-WEBAPP · OPS-022</p>
            <h1>Inventory Ledger</h1>
          </div>
          <Link href="/" className="button button-secondary">Trang chủ</Link>
        </header>
        <section className="content-card">
          <p className="permission-note">
            Inventory ledger và stock snapshot dành cho OWNER/ADMIN và WAREHOUSE.
          </p>
        </section>
      </main>
    );
  }

  let products: Product[];
  let variants: Variant[];
  let stock: Stock[];
  let movements: Movement[];

  try {
    [products, variants, stock, movements] = await Promise.all([
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
    ]);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

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
          <p className="eyebrow">OPS-WEBAPP · OPS-022</p>
          <h1>Inventory Ledger</h1>
          <p className="muted">
            Single-warehouse stock truth: on hand / reserved / available được dẫn xuất từ immutable inventory movements.
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

      <section className="metric-grid">
        <article className="metric-card"><span>SKU tracked</span><strong>{variants.length}</strong></article>
        <article className="metric-card"><span>On hand</span><strong className="metric-small">{num(totalOnHand)}</strong></article>
        <article className="metric-card"><span>Reserved</span><strong className="metric-small">{num(totalReserved)}</strong></article>
        <article className="metric-card"><span>Available</span><strong className="metric-small">{num(totalAvailable)}</strong></article>
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
          OPS-022 hiện post GOODS_RECEIPT vào ledger và append cost history. SALES_RESERVATION / RESERVATION_RELEASE / SALES_ISSUE thuộc OPS-023.
          STOCKTAKE_ADJUSTMENT / ADJUSTMENT_IN / ADJUSTMENT_OUT và low-stock workflow thuộc OPS-024.
        </p>
      </section>
    </main>
  );
}

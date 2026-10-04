import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Supplier = {
  id: string;
  supplier_code: string | null;
  supplier_name: string;
  contact_name: string | null;
  phone: string | null;
  address: string | null;
  notes: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

type SupplierProduct = {
  id: string;
  product_variant_id: string;
  supplier_sku: string | null;
  purchase_unit: string | null;
  is_preferred: boolean;
  is_active: boolean;
};

type ProductVariant = {
  id: string;
  sku_code: string;
  variant_name: string | null;
  product_id: string;
  default_purchase_unit: string | null;
  is_active: boolean;
};

type Product = {
  id: string;
  name: string;
};

type PurchaseOrder = {
  id: string;
  po_number: string;
  status: string;
  order_date: string;
  expected_receipt_date: string | null;
  actual_receipt_date: string | null;
  freight_amount: number;
  currency_code: string;
};

type PurchaseOrderItem = {
  purchase_order_id: string;
  product_variant_id: string;
  package_quantity: number;
  purchase_unit: string;
  unit_cost_per_purchase_unit: number;
  line_subtotal: number;
};

type CostHistory = {
  id: string;
  product_variant_id: string;
  effective_at: string;
  purchase_unit: string;
  purchase_price_per_purchase_unit: number;
  landed_cost_per_base_unit: number;
  currency_code: string;
  source_reference: string | null;
};

type SupplierDetailProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{
    saved?: string;
    product_added?: string;
    error?: string;
  }>;
};

function money(value: number, currency = "VND") {
  return new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency,
    maximumFractionDigits: currency === "VND" ? 0 : 2,
  }).format(Number(value));
}

function date(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("vi-VN").format(new Date(value));
}

export default async function SupplierDetailPage({
  params,
  searchParams,
}: SupplierDetailProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    redirect("/login");
  }

  const roles = await getCurrentRoles();
  const canManage = roles.has("OWNER_ADMIN");
  const canViewFinancial = canManage || roles.has("ACCOUNTING");
  const { id } = await params;
  const state = await searchParams;
  const encodedId = encodeURIComponent(id);

  let supplierRows: Supplier[];
  try {
    supplierRows = await supabaseRest<Supplier[]>(
      `suppliers?id=eq.${encodedId}&select=id,supplier_code,supplier_name,contact_name,phone,address,notes,is_active,created_at,updated_at`,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const supplier = supplierRows[0];
  if (!supplier) {
    notFound();
  }

  const suppliedProducts = await supabaseRest<SupplierProduct[]>(
    `supplier_products?supplier_id=eq.${encodedId}&select=id,product_variant_id,supplier_sku,purchase_unit,is_preferred,is_active&order=is_preferred.desc,created_at.desc&limit=200`,
  );

  const suppliedVariantIds = [
    ...new Set(suppliedProducts.map((row) => row.product_variant_id)),
  ];

  const allVariants = canManage
    ? await supabaseRest<ProductVariant[]>(
        "product_variants?select=id,sku_code,variant_name,product_id,default_purchase_unit,is_active&is_active=eq.true&order=sku_code.asc&limit=500",
      )
    : [];

  const referencedVariantIds = [
    ...new Set([...suppliedVariantIds, ...allVariants.map((row) => row.id)]),
  ];

  const variants =
    referencedVariantIds.length > 0
      ? await supabaseRest<ProductVariant[]>(
          `product_variants?id=in.(${referencedVariantIds.join(",")})&select=id,sku_code,variant_name,product_id,default_purchase_unit,is_active`,
        )
      : [];

  const productIds = [...new Set(variants.map((variant) => variant.product_id))];
  const products =
    productIds.length > 0
      ? await supabaseRest<Product[]>(
          `products?id=in.(${productIds.join(",")})&select=id,name`,
        )
      : [];

  let orders: PurchaseOrder[] = [];
  let orderItems: PurchaseOrderItem[] = [];
  let costs: CostHistory[] = [];

  if (canViewFinancial) {
    orders = await supabaseRest<PurchaseOrder[]>(
      `purchase_orders?supplier_id=eq.${encodedId}&select=id,po_number,status,order_date,expected_receipt_date,actual_receipt_date,freight_amount,currency_code&order=order_date.desc,created_at.desc&limit=100`,
    );

    if (orders.length > 0) {
      orderItems = await supabaseRest<PurchaseOrderItem[]>(
        `purchase_order_items?purchase_order_id=in.(${orders
          .map((order) => order.id)
          .join(",")})&select=purchase_order_id,product_variant_id,package_quantity,purchase_unit,unit_cost_per_purchase_unit,line_subtotal&limit=500`,
      );
    }

    costs = await supabaseRest<CostHistory[]>(
      `purchase_cost_history?supplier_id=eq.${encodedId}&select=id,product_variant_id,effective_at,purchase_unit,purchase_price_per_purchase_unit,landed_cost_per_base_unit,currency_code,source_reference&order=effective_at.desc&limit=200`,
    );
  }

  const variantsById = new Map(variants.map((variant) => [variant.id, variant]));
  const productsById = new Map(products.map((product) => [product.id, product]));

  const orderTotals = new Map<string, number>();
  for (const item of orderItems) {
    orderTotals.set(
      item.purchase_order_id,
      (orderTotals.get(item.purchase_order_id) ?? 0) + Number(item.line_subtotal),
    );
  }

  const latestCosts = new Map<string, CostHistory>();
  for (const row of costs) {
    if (!latestCosts.has(row.product_variant_id)) {
      latestCosts.set(row.product_variant_id, row);
    }
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <Link href="/suppliers" className="text-link">
            ← Danh sách nhà cung cấp
          </Link>
          <p className="eyebrow">SUPPLIER PROFILE</p>
          <h1>{supplier.supplier_name}</h1>
          <p className="muted">
            {supplier.supplier_code ?? "Chưa có mã"} ·{" "}
            {supplier.is_active ? "Đang hoạt động" : "Ngưng hoạt động"}
          </p>
        </div>
        <form action="/api/auth/logout" method="post">
          <button type="submit" className="button button-secondary">
            Đăng xuất
          </button>
        </form>
      </header>

      {state.saved ? (
        <div className="alert alert-success">Đã cập nhật hồ sơ nhà cung cấp.</div>
      ) : null}
      {state.product_added ? (
        <div className="alert alert-success">Đã thêm sản phẩm cung ứng.</div>
      ) : null}
      {state.error ? (
        <div className="alert alert-error">
          {state.error === "supplier_name"
            ? "Tên nhà cung cấp là bắt buộc."
            : state.error === "product_variant"
              ? "Vui lòng chọn sản phẩm."
              : "Không thể lưu dữ liệu. Kiểm tra quyền hoặc dữ liệu trùng."}
        </div>
      ) : null}

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>Thông tin nhà cung cấp</h2>
          {canManage ? (
            <form
              action={`/api/suppliers/${supplier.id}`}
              method="post"
              className="form-stack"
            >
              <div className="form-row">
                <label>
                  Tên nhà cung cấp *
                  <input
                    name="supplier_name"
                    defaultValue={supplier.supplier_name}
                    required
                  />
                </label>
                <label>
                  Mã nhà cung cấp
                  <input
                    name="supplier_code"
                    defaultValue={supplier.supplier_code ?? ""}
                  />
                </label>
              </div>
              <div className="form-row">
                <label>
                  Người liên hệ
                  <input
                    name="contact_name"
                    defaultValue={supplier.contact_name ?? ""}
                  />
                </label>
                <label>
                  Điện thoại
                  <input name="phone" defaultValue={supplier.phone ?? ""} />
                </label>
              </div>
              <label>
                Địa chỉ
                <textarea
                  name="address"
                  rows={2}
                  defaultValue={supplier.address ?? ""}
                />
              </label>
              <label>
                Ghi chú
                <textarea
                  name="notes"
                  rows={3}
                  defaultValue={supplier.notes ?? ""}
                />
              </label>
              <label className="checkbox-row">
                <input
                  type="checkbox"
                  name="is_active"
                  defaultChecked={supplier.is_active}
                />
                Nhà cung cấp đang hoạt động
              </label>
              <button type="submit" className="button button-primary">
                Lưu hồ sơ
              </button>
            </form>
          ) : (
            <div className="stack-list">
              <div className="stack-item">
                <span>Người liên hệ</span>
                <strong>{supplier.contact_name ?? "—"}</strong>
              </div>
              <div className="stack-item">
                <span>Điện thoại</span>
                <strong>{supplier.phone ?? "—"}</strong>
              </div>
              <div className="stack-item">
                <span>Địa chỉ</span>
                <strong>{supplier.address ?? "—"}</strong>
              </div>
              <div className="stack-item">
                <span>Ghi chú</span>
                <strong>{supplier.notes ?? "—"}</strong>
              </div>
            </div>
          )}
        </article>

        <aside className="content-card">
          <h2>Sản phẩm cung ứng</h2>
          <p className="muted">{suppliedProducts.length} liên kết đang hiển thị.</p>
          <div className="stack-list">
            {suppliedProducts.map((row) => {
              const variant = variantsById.get(row.product_variant_id);
              const product = variant
                ? productsById.get(variant.product_id)
                : undefined;
              return (
                <div className="stack-item" key={row.id}>
                  <div>
                    <strong>{variant?.sku_code ?? "SKU"}</strong>
                    <div className="subtle">
                      {product?.name ?? variant?.variant_name ?? "Sản phẩm"}
                    </div>
                  </div>
                  <div className="align-right">
                    <strong>{row.purchase_unit ?? "—"}</strong>
                    <div className="subtle">
                      {row.is_preferred ? "Ưu tiên" : row.supplier_sku ?? "—"}
                    </div>
                  </div>
                </div>
              );
            })}
            {suppliedProducts.length === 0 ? (
              <p className="empty-state">Chưa liên kết sản phẩm.</p>
            ) : null}
          </div>
        </aside>
      </section>

      {canManage ? (
        <section className="content-card">
          <h2>Thêm sản phẩm cung ứng</h2>
          <form
            action={`/api/suppliers/${supplier.id}/products`}
            method="post"
            className="form-row"
          >
            <label>
              SKU *
              <select name="product_variant_id" required>
                <option value="">Chọn SKU</option>
                {allVariants.map((variant) => {
                  const product = productsById.get(variant.product_id);
                  return (
                    <option value={variant.id} key={variant.id}>
                      {variant.sku_code} ·{" "}
                      {product?.name ?? variant.variant_name ?? "Sản phẩm"}
                    </option>
                  );
                })}
              </select>
            </label>
            <label>
              SKU phía nhà cung cấp
              <input name="supplier_sku" />
            </label>
            <label>
              Đơn vị mua
              <input name="purchase_unit" placeholder="box, carton, piece..." />
            </label>
            <label className="checkbox-row">
              <input type="checkbox" name="is_preferred" />
              Nhà cung cấp ưu tiên cho SKU
            </label>
            <button type="submit" className="button button-primary">
              Thêm liên kết
            </button>
          </form>
        </section>
      ) : null}

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>Lịch sử mua hàng</h2>
          {!canViewFinancial ? (
            <p className="permission-note">
              WAREHOUSE được xem hồ sơ và sản phẩm cung ứng nhưng không được xem
              đơn mua hàng chứa dữ liệu tài chính/cost.
            </p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>PO</th>
                    <th>Ngày</th>
                    <th>Trạng thái</th>
                    <th>Dự kiến nhận</th>
                    <th>Thực nhận</th>
                    <th>Tổng</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.map((order) => (
                    <tr key={order.id}>
                      <td>{order.po_number}</td>
                      <td>{date(order.order_date)}</td>
                      <td>{order.status}</td>
                      <td>{date(order.expected_receipt_date)}</td>
                      <td>{date(order.actual_receipt_date)}</td>
                      <td>
                        {money(
                          (orderTotals.get(order.id) ?? 0) +
                            Number(order.freight_amount),
                          order.currency_code,
                        )}
                      </td>
                    </tr>
                  ))}
                  {orders.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="empty-state">
                        Chưa có lịch sử mua hàng.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </div>
          )}
        </article>

        <aside className="content-card">
          <h2>Giá mua gần nhất</h2>
          {!canViewFinancial ? (
            <p className="permission-note">
              Giá mua và landed cost chỉ dành cho OWNER/ADMIN và ACCOUNTING.
            </p>
          ) : (
            <div className="stack-list">
              {[...latestCosts.values()].map((cost) => {
                const variant = variantsById.get(cost.product_variant_id);
                const product = variant
                  ? productsById.get(variant.product_id)
                  : undefined;
                return (
                  <div className="stack-item" key={cost.id}>
                    <div>
                      <strong>{variant?.sku_code ?? "SKU"}</strong>
                      <div className="subtle">
                        {product?.name ?? variant?.variant_name ?? "Sản phẩm"} ·{" "}
                        {date(cost.effective_at)}
                      </div>
                    </div>
                    <div className="align-right">
                      <strong>
                        {money(
                          cost.purchase_price_per_purchase_unit,
                          cost.currency_code,
                        )}
                      </strong>
                      <div className="subtle">
                        / {cost.purchase_unit} · landed/base{" "}
                        {money(cost.landed_cost_per_base_unit, cost.currency_code)}
                      </div>
                    </div>
                  </div>
                );
              })}
              {latestCosts.size === 0 ? (
                <p className="empty-state">Chưa có lịch sử giá mua.</p>
              ) : null}
            </div>
          )}
        </aside>
      </section>

      <section className="content-card">
        <h2>Phạm vi V1</h2>
        <p className="muted">
          Supplier debt / công nợ nhà cung cấp không thuộc phạm vi V1. Hệ thống
          theo SOT giả định đơn mua được thanh toán ngay trong workflow mua hàng.
        </p>
      </section>
    </main>
  );
}

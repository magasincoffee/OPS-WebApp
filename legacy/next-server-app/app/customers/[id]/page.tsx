import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Customer = {
  id: string;
  customer_code: string | null;
  display_name: string;
  brand_name: string | null;
  company_name: string | null;
  contact_name: string | null;
  phone: string | null;
  address: string | null;
  notes: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

type SalesOrder = {
  id: string;
  order_number: string;
  order_status: string;
  print_status: string;
  warehouse_status: string;
  payment_status: string;
  delivery_status: string;
  order_date: string;
  requested_due_date: string | null;
  currency_code: string;
};

type SalesOrderItem = {
  sales_order_id: string;
  product_variant_id: string;
  sale_unit: string;
  sale_quantity: number;
  base_quantity: number;
  line_total: number;
  print_mode: string;
};

type ProductVariant = {
  id: string;
  sku_code: string;
  variant_name: string | null;
  product_id: string;
};

type Product = {
  id: string;
  name: string;
};

type Payment = {
  id: string;
  sales_order_id: string | null;
  amount: number;
  payment_date: string;
  payment_method: string;
  status: string;
  reference: string | null;
};

type Receivable = {
  sales_order_id: string;
  order_number: string;
  order_total_amount: number;
  valid_payment_amount: number;
  receivable_amount: number;
  currency_code: string;
  payment_status: string;
  order_status: string;
  order_date: string;
};

type Activity = {
  id: string;
  action_type: string;
  change_summary: string | null;
  occurred_at: string;
  actor_user_id: string | null;
};

type CustomerDetailProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ saved?: string; error?: string }>;
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

async function optionalQuery<T>(path: string): Promise<T | null> {
  try {
    return await supabaseRest<T>(path);
  } catch (error) {
    if (
      error instanceof SupabaseRestError &&
      (error.status === 401 || error.status === 403)
    ) {
      return null;
    }
    throw error;
  }
}

export default async function CustomerDetailPage({
  params,
  searchParams,
}: CustomerDetailProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    redirect("/login");
  }

  const { id } = await params;
  const state = await searchParams;
  const encodedId = encodeURIComponent(id);

  let customerRows: Customer[];
  try {
    customerRows = await supabaseRest<Customer[]>(
      `customers?id=eq.${encodedId}&select=id,customer_code,display_name,brand_name,company_name,contact_name,phone,address,notes,is_active,created_at,updated_at`,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const customer = customerRows[0];
  if (!customer) {
    notFound();
  }

  const orders = await supabaseRest<SalesOrder[]>(
    `sales_orders?customer_id=eq.${encodedId}&select=id,order_number,order_status,print_status,warehouse_status,payment_status,delivery_status,order_date,requested_due_date,currency_code&order=order_date.desc,created_at.desc&limit=100`,
  );

  const receivables =
    (await optionalQuery<Receivable[]>(
      `sales_receivable_followup?customer_id=eq.${encodedId}&select=sales_order_id,order_number,order_total_amount,valid_payment_amount,receivable_amount,currency_code,payment_status,order_status,order_date&order=order_date.desc`,
    )) ?? [];

  const payments = await optionalQuery<Payment[]>(
    `customer_payments?customer_id=eq.${encodedId}&select=id,sales_order_id,amount,payment_date,payment_method,status,reference&order=payment_date.desc,created_at.desc&limit=100`,
  );

  const activity =
    (await optionalQuery<Activity[]>(
      `activity_logs?linked_entity_type=eq.CUSTOMER&linked_entity_id=eq.${encodedId}&select=id,action_type,change_summary,occurred_at,actor_user_id&order=occurred_at.desc&limit=100`,
    )) ?? [];

  const orderIds = orders.map((order) => order.id);
  let items: SalesOrderItem[] = [];
  let variants: ProductVariant[] = [];
  let products: Product[] = [];

  if (orderIds.length > 0) {
    const orderFilter = orderIds.join(",");
    items = await supabaseRest<SalesOrderItem[]>(
      `sales_order_items?sales_order_id=in.(${orderFilter})&select=sales_order_id,product_variant_id,sale_unit,sale_quantity,base_quantity,line_total,print_mode&order=created_at.desc&limit=500`,
    );

    const variantIds = [...new Set(items.map((item) => item.product_variant_id))];
    if (variantIds.length > 0) {
      variants = await supabaseRest<ProductVariant[]>(
        `product_variants?id=in.(${variantIds.join(",")})&select=id,sku_code,variant_name,product_id`,
      );

      const productIds = [...new Set(variants.map((variant) => variant.product_id))];
      if (productIds.length > 0) {
        products = await supabaseRest<Product[]>(
          `products?id=in.(${productIds.join(",")})&select=id,name`,
        );
      }
    }
  }

  const variantsById = new Map(variants.map((variant) => [variant.id, variant]));
  const productsById = new Map(products.map((product) => [product.id, product]));
  const orderById = new Map(orders.map((order) => [order.id, order]));

  const outstandingReceivable = receivables.reduce(
    (sum, row) => sum + Math.max(Number(row.receivable_amount), 0),
    0,
  );
  const activeOrderCount = orders.filter(
    (order) =>
      order.order_status !== "COMPLETED" && order.order_status !== "CANCELLED",
  ).length;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <Link href="/customers" className="text-link">
            ← Danh sách khách hàng
          </Link>
          <p className="eyebrow">CUSTOMER PROFILE</p>
          <h1>{customer.display_name}</h1>
          <p className="muted">
            {customer.customer_code ?? "Chưa có mã"} ·{" "}
            {customer.is_active ? "Đang hoạt động" : "Ngưng hoạt động"}
          </p>
        </div>
        <form action="/api/auth/logout" method="post">
          <button type="submit" className="button button-secondary">
            Đăng xuất
          </button>
        </form>
      </header>

      {state.saved ? (
        <div className="alert alert-success">Đã cập nhật hồ sơ khách hàng.</div>
      ) : null}
      {state.error ? (
        <div className="alert alert-error">
          {state.error === "display_name"
            ? "Tên hiển thị là bắt buộc."
            : "Không thể cập nhật hồ sơ. Kiểm tra quyền tài khoản hoặc dữ liệu."}
        </div>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card">
          <span>Đơn hàng</span>
          <strong>{orders.length}</strong>
        </article>
        <article className="metric-card">
          <span>Đơn đang xử lý</span>
          <strong>{activeOrderCount}</strong>
        </article>
        <article className="metric-card">
          <span>Công nợ hiện tại</span>
          <strong>{money(outstandingReceivable)}</strong>
        </article>
        <article className="metric-card">
          <span>Lần cập nhật gần nhất</span>
          <strong className="metric-small">{date(customer.updated_at)}</strong>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="content-card">
          <div className="section-heading">
            <div>
              <h2>Thông tin khách hàng</h2>
              <p className="muted">
                SALES và OWNER/ADMIN có thể cập nhật. ACCOUNTING được xem.
              </p>
            </div>
          </div>

          <form
            action={`/api/customers/${customer.id}`}
            method="post"
            className="form-stack"
          >
            <div className="form-row">
              <label>
                Tên hiển thị *
                <input
                  name="display_name"
                  defaultValue={customer.display_name}
                  required
                />
              </label>
              <label>
                Mã khách hàng
                <input
                  name="customer_code"
                  defaultValue={customer.customer_code ?? ""}
                />
              </label>
            </div>
            <div className="form-row">
              <label>
                Thương hiệu
                <input
                  name="brand_name"
                  defaultValue={customer.brand_name ?? ""}
                />
              </label>
              <label>
                Công ty
                <input
                  name="company_name"
                  defaultValue={customer.company_name ?? ""}
                />
              </label>
            </div>
            <div className="form-row">
              <label>
                Người liên hệ
                <input
                  name="contact_name"
                  defaultValue={customer.contact_name ?? ""}
                />
              </label>
              <label>
                Điện thoại
                <input name="phone" defaultValue={customer.phone ?? ""} />
              </label>
            </div>
            <label>
              Địa chỉ
              <textarea
                name="address"
                rows={2}
                defaultValue={customer.address ?? ""}
              />
            </label>
            <label>
              Ghi chú
              <textarea
                name="notes"
                rows={3}
                defaultValue={customer.notes ?? ""}
              />
            </label>
            <label className="checkbox-row">
              <input
                type="checkbox"
                name="is_active"
                defaultChecked={customer.is_active}
              />
              Khách hàng đang hoạt động
            </label>
            <button type="submit" className="button button-primary">
              Lưu hồ sơ
            </button>
          </form>
        </article>

        <aside className="content-card">
          <h2>Công nợ theo đơn</h2>
          <div className="stack-list">
            {receivables.map((row) => (
              <div key={row.sales_order_id} className="stack-item">
                <div>
                  <strong>{row.order_number}</strong>
                  <div className="subtle">
                    {date(row.order_date)} · {row.payment_status}
                  </div>
                </div>
                <div className="align-right">
                  <strong>{money(row.receivable_amount, row.currency_code)}</strong>
                  <div className="subtle">
                    / {money(row.order_total_amount, row.currency_code)}
                  </div>
                </div>
              </div>
            ))}
            {receivables.length === 0 ? (
              <p className="empty-state">Chưa có công nợ theo đơn.</p>
            ) : null}
          </div>
        </aside>
      </section>

      <section className="content-card">
        <h2>Lịch sử đơn hàng</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Đơn</th>
                <th>Ngày</th>
                <th>Đơn hàng</th>
                <th>In</th>
                <th>Kho</th>
                <th>Thanh toán</th>
                <th>Giao hàng</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr key={order.id}>
                  <td>{order.order_number}</td>
                  <td>{date(order.order_date)}</td>
                  <td>{order.order_status}</td>
                  <td>{order.print_status}</td>
                  <td>{order.warehouse_status}</td>
                  <td>{order.payment_status}</td>
                  <td>{order.delivery_status}</td>
                </tr>
              ))}
              {orders.length === 0 ? (
                <tr>
                  <td colSpan={7} className="empty-state">
                    Chưa có đơn hàng.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="content-card">
        <h2>Lịch sử mua sản phẩm</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Đơn</th>
                <th>SKU</th>
                <th>Sản phẩm</th>
                <th>Số lượng</th>
                <th>Loại</th>
                <th>Thành tiền</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item, index) => {
                const variant = variantsById.get(item.product_variant_id);
                const product = variant
                  ? productsById.get(variant.product_id)
                  : undefined;
                const order = orderById.get(item.sales_order_id);

                return (
                  <tr key={`${item.sales_order_id}-${item.product_variant_id}-${index}`}>
                    <td>{order?.order_number ?? "—"}</td>
                    <td>{variant?.sku_code ?? "—"}</td>
                    <td>
                      {product?.name ?? variant?.variant_name ?? "Sản phẩm"}
                    </td>
                    <td>
                      {Number(item.sale_quantity).toLocaleString("vi-VN")}{" "}
                      {item.sale_unit}
                    </td>
                    <td>{item.print_mode}</td>
                    <td>
                      {money(
                        Number(item.line_total),
                        order?.currency_code ?? "VND",
                      )}
                    </td>
                  </tr>
                );
              })}
              {items.length === 0 ? (
                <tr>
                  <td colSpan={6} className="empty-state">
                    Chưa có lịch sử mua sản phẩm.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>Lịch sử thanh toán</h2>
          {payments === null ? (
            <p className="permission-note">
              Vai trò hiện tại không có quyền xem chi tiết thanh toán. SALES vẫn
              xem được công nợ tổng hợp để theo dõi khách hàng.
            </p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Ngày</th>
                    <th>Số tiền</th>
                    <th>Phương thức</th>
                    <th>Trạng thái</th>
                    <th>Tham chiếu</th>
                  </tr>
                </thead>
                <tbody>
                  {payments.map((payment) => (
                    <tr key={payment.id}>
                      <td>{date(payment.payment_date)}</td>
                      <td>{money(payment.amount)}</td>
                      <td>{payment.payment_method}</td>
                      <td>{payment.status}</td>
                      <td>{payment.reference ?? "—"}</td>
                    </tr>
                  ))}
                  {payments.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="empty-state">
                        Chưa có thanh toán.
                      </td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </div>
          )}
        </article>

        <aside className="content-card">
          <h2>Lịch sử hoạt động</h2>
          <div className="timeline">
            {activity.map((entry) => (
              <div key={entry.id} className="timeline-item">
                <div className="timeline-dot" />
                <div>
                  <strong>{entry.change_summary ?? entry.action_type}</strong>
                  <div className="subtle">{date(entry.occurred_at)}</div>
                </div>
              </div>
            ))}
            {activity.length === 0 ? (
              <p className="empty-state">Chưa có hoạt động được ghi nhận.</p>
            ) : null}
          </div>
        </aside>
      </section>
    </main>
  );
}

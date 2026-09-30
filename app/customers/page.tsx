import Link from "next/link";
import { redirect } from "next/navigation";
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
  updated_at: string;
};

type CustomerPageProps = {
  searchParams: Promise<{ q?: string; error?: string }>;
};

function matchesSearch(customer: Customer, query: string) {
  const haystack = [
    customer.customer_code,
    customer.display_name,
    customer.brand_name,
    customer.company_name,
    customer.contact_name,
    customer.phone,
  ]
    .filter(Boolean)
    .join(" ")
    .toLocaleLowerCase("vi");

  return haystack.includes(query.toLocaleLowerCase("vi"));
}

export default async function CustomersPage({
  searchParams,
}: CustomerPageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    redirect("/login");
  }

  const { q = "", error } = await searchParams;
  let customers: Customer[] = [];

  try {
    customers = await supabaseRest<Customer[]>(
      "customers?select=id,customer_code,display_name,brand_name,company_name,contact_name,phone,address,notes,is_active,updated_at&order=updated_at.desc&limit=200",
    );
  } catch (requestError) {
    if (
      requestError instanceof SupabaseRestError &&
      requestError.status === 401
    ) {
      redirect("/login?error=session");
    }

    return (
      <main className="app-shell">
        <section className="content-card">
          <h1>Khách hàng</h1>
          <div className="alert alert-error">
            Không thể tải dữ liệu khách hàng. Kiểm tra cấu hình Supabase và quyền
            tài khoản.
          </div>
        </section>
      </main>
    );
  }

  const filteredCustomers = q.trim()
    ? customers.filter((customer) => matchesSearch(customer, q.trim()))
    : customers;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-010</p>
          <h1>Khách hàng</h1>
          <p className="muted">
            Hồ sơ trung tâm cho bán hàng, công nợ và lịch sử giao dịch.
          </p>
        </div>
        <form action="/api/auth/logout" method="post">
          <button type="submit" className="button button-secondary">
            Đăng xuất
          </button>
        </form>
      </header>

      {error ? (
        <div className="alert alert-error">
          {error === "display_name"
            ? "Tên hiển thị là bắt buộc."
            : "Không thể lưu khách hàng. Kiểm tra mã khách hàng trùng hoặc quyền tài khoản."}
        </div>
      ) : null}

      <section className="dashboard-grid">
        <article className="content-card">
          <div className="section-heading">
            <div>
              <h2>Danh sách khách hàng</h2>
              <p className="muted">{filteredCustomers.length} hồ sơ hiển thị</p>
            </div>
            <form method="get" className="search-form">
              <input
                name="q"
                defaultValue={q}
                placeholder="Tìm tên, mã, thương hiệu, điện thoại..."
              />
              <button className="button button-secondary" type="submit">
                Tìm
              </button>
            </form>
          </div>

          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Mã</th>
                  <th>Khách hàng</th>
                  <th>Liên hệ</th>
                  <th>Điện thoại</th>
                  <th>Trạng thái</th>
                </tr>
              </thead>
              <tbody>
                {filteredCustomers.map((customer) => (
                  <tr key={customer.id}>
                    <td>{customer.customer_code ?? "—"}</td>
                    <td>
                      <Link
                        href={`/customers/${customer.id}`}
                        className="row-link"
                      >
                        {customer.display_name}
                      </Link>
                      <div className="subtle">
                        {customer.brand_name ?? customer.company_name ?? ""}
                      </div>
                    </td>
                    <td>{customer.contact_name ?? "—"}</td>
                    <td>{customer.phone ?? "—"}</td>
                    <td>
                      <span
                        className={
                          customer.is_active
                            ? "status status-active"
                            : "status status-muted"
                        }
                      >
                        {customer.is_active ? "Đang hoạt động" : "Ngưng hoạt động"}
                      </span>
                    </td>
                  </tr>
                ))}
                {filteredCustomers.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="empty-state">
                      Chưa có khách hàng phù hợp.
                    </td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </div>
        </article>

        <aside className="content-card">
          <h2>Tạo khách hàng</h2>
          <p className="muted">
            OWNER/ADMIN và SALES có thể tạo hồ sơ. RLS sẽ từ chối vai trò không
            được phép.
          </p>
          <form action="/api/customers" method="post" className="form-stack">
            <label>
              Tên hiển thị *
              <input name="display_name" required />
            </label>
            <div className="form-row">
              <label>
                Mã khách hàng
                <input name="customer_code" />
              </label>
              <label>
                Điện thoại
                <input name="phone" />
              </label>
            </div>
            <label>
              Thương hiệu
              <input name="brand_name" />
            </label>
            <label>
              Công ty
              <input name="company_name" />
            </label>
            <label>
              Người liên hệ
              <input name="contact_name" />
            </label>
            <label>
              Địa chỉ
              <textarea name="address" rows={2} />
            </label>
            <label>
              Ghi chú
              <textarea name="notes" rows={3} />
            </label>
            <button type="submit" className="button button-primary">
              Tạo khách hàng
            </button>
          </form>
        </aside>
      </section>
    </main>
  );
}

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
  supplier_code: string | null;
  supplier_name: string;
  contact_name: string | null;
  phone: string | null;
  address: string | null;
  notes: string | null;
  is_active: boolean;
  updated_at: string;
};

type SupplierPageProps = {
  searchParams: Promise<{ q?: string; error?: string }>;
};

function matchesSearch(supplier: Supplier, query: string) {
  const haystack = [
    supplier.supplier_code,
    supplier.supplier_name,
    supplier.contact_name,
    supplier.phone,
    supplier.address,
  ]
    .filter(Boolean)
    .join(" ")
    .toLocaleLowerCase("vi");

  return haystack.includes(query.toLocaleLowerCase("vi"));
}

export default async function SuppliersPage({
  searchParams,
}: SupplierPageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) {
    redirect("/login");
  }

  const roles = await getCurrentRoles();
  const canView = ["OWNER_ADMIN", "ACCOUNTING", "WAREHOUSE"].some((role) =>
    roles.has(role),
  );
  const canManage = roles.has("OWNER_ADMIN");
  const { q = "", error } = await searchParams;

  let suppliers: Supplier[] = [];
  try {
    suppliers = await supabaseRest<Supplier[]>(
      "suppliers?select=id,supplier_code,supplier_name,contact_name,phone,address,notes,is_active,updated_at&order=updated_at.desc&limit=200",
    );
  } catch (requestError) {
    if (
      requestError instanceof SupabaseRestError &&
      requestError.status === 401
    ) {
      redirect("/login?error=session");
    }
    throw requestError;
  }

  const filteredSuppliers = q.trim()
    ? suppliers.filter((supplier) => matchesSearch(supplier, q.trim()))
    : suppliers;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-011</p>
          <h1>Nhà cung cấp</h1>
          <p className="muted">
            Hồ sơ nhà cung cấp, sản phẩm cung ứng và lịch sử mua hàng theo quyền.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/customers" className="button button-secondary">
            Khách hàng
          </Link>
          <form action="/api/auth/logout" method="post">
            <button type="submit" className="button button-secondary">
              Đăng xuất
            </button>
          </form>
        </div>
      </header>

      {!canView ? (
        <div className="alert alert-error">
          Vai trò hiện tại không có quyền truy cập dữ liệu nhà cung cấp.
        </div>
      ) : null}

      {error ? (
        <div className="alert alert-error">
          {error === "supplier_name"
            ? "Tên nhà cung cấp là bắt buộc."
            : "Không thể lưu nhà cung cấp. Kiểm tra quyền hoặc mã nhà cung cấp trùng."}
        </div>
      ) : null}

      <section className={canManage ? "dashboard-grid" : undefined}>
        <article className="content-card">
          <div className="section-heading">
            <div>
              <h2>Danh sách nhà cung cấp</h2>
              <p className="muted">{filteredSuppliers.length} hồ sơ hiển thị</p>
            </div>
            <form method="get" className="search-form">
              <input
                name="q"
                defaultValue={q}
                placeholder="Tìm tên, mã, liên hệ, điện thoại..."
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
                  <th>Nhà cung cấp</th>
                  <th>Liên hệ</th>
                  <th>Điện thoại</th>
                  <th>Trạng thái</th>
                </tr>
              </thead>
              <tbody>
                {filteredSuppliers.map((supplier) => (
                  <tr key={supplier.id}>
                    <td>{supplier.supplier_code ?? "—"}</td>
                    <td>
                      <Link
                        href={`/suppliers/${supplier.id}`}
                        className="row-link"
                      >
                        {supplier.supplier_name}
                      </Link>
                    </td>
                    <td>{supplier.contact_name ?? "—"}</td>
                    <td>{supplier.phone ?? "—"}</td>
                    <td>
                      <span
                        className={
                          supplier.is_active
                            ? "status status-active"
                            : "status status-muted"
                        }
                      >
                        {supplier.is_active ? "Đang hoạt động" : "Ngưng hoạt động"}
                      </span>
                    </td>
                  </tr>
                ))}
                {filteredSuppliers.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="empty-state">
                      Chưa có nhà cung cấp phù hợp hoặc vai trò hiện tại không có
                      quyền xem.
                    </td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </div>
        </article>

        {canManage ? (
          <aside className="content-card">
            <h2>Tạo nhà cung cấp</h2>
            <p className="muted">
              Chỉ OWNER/ADMIN quản lý master nhà cung cấp.
            </p>
            <form action="/api/suppliers" method="post" className="form-stack">
              <label>
                Tên nhà cung cấp *
                <input name="supplier_name" required />
              </label>
              <div className="form-row">
                <label>
                  Mã nhà cung cấp
                  <input name="supplier_code" />
                </label>
                <label>
                  Điện thoại
                  <input name="phone" />
                </label>
              </div>
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
                Tạo nhà cung cấp
              </button>
            </form>
          </aside>
        ) : null}
      </section>
    </main>
  );
}

import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Category = {
  id: string;
  category_code: string | null;
  name: string;
  description: string | null;
  is_active: boolean;
};

type Product = {
  id: string;
  category_id: string | null;
  name: string;
  product_type: string | null;
  description: string | null;
  is_active: boolean;
};

type Variant = {
  id: string;
  product_id: string;
  sku_code: string;
  variant_name: string | null;
  capacity_value: number | null;
  capacity_unit: string | null;
  base_inventory_unit: string;
  default_purchase_unit: string | null;
  minimum_stock_quantity: number;
  is_active: boolean;
};

type Packaging = {
  id: string;
  product_variant_id: string;
  is_active: boolean;
};

type PageProps = {
  searchParams: Promise<{
    q?: string;
    error?: string;
    category_saved?: string;
    product_saved?: string;
    sku_saved?: string;
  }>;
};

function compactNumber(value: number | null) {
  if (value === null) return "—";
  return new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 6 }).format(Number(value));
}

export default async function ProductsPage({ searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const canManage = roles.has("OWNER_ADMIN");
  const state = await searchParams;

  let categories: Category[];
  let products: Product[];
  let variants: Variant[];
  let packaging: Packaging[];

  try {
    [categories, products, variants, packaging] = await Promise.all([
      supabaseRest<Category[]>(
        "product_categories?select=id,category_code,name,description,is_active&order=name.asc&limit=300",
      ),
      supabaseRest<Product[]>(
        "products?select=id,category_id,name,product_type,description,is_active&order=name.asc&limit=1000",
      ),
      supabaseRest<Variant[]>(
        "product_variants?select=id,product_id,sku_code,variant_name,capacity_value,capacity_unit,base_inventory_unit,default_purchase_unit,minimum_stock_quantity,is_active&order=sku_code.asc&limit=2000",
      ),
      supabaseRest<Packaging[]>(
        "product_packaging?select=id,product_variant_id,is_active&limit=5000",
      ),
    ]);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) {
      redirect("/login?error=session");
    }
    throw error;
  }

  const categoryById = new Map(categories.map((row) => [row.id, row]));
  const productById = new Map(products.map((row) => [row.id, row]));
  const packageCount = new Map<string, number>();
  for (const row of packaging) {
    if (row.is_active) {
      packageCount.set(row.product_variant_id, (packageCount.get(row.product_variant_id) ?? 0) + 1);
    }
  }

  const query = (state.q ?? "").trim().toLocaleLowerCase("vi");
  const visibleVariants = query
    ? variants.filter((variant) => {
        const product = productById.get(variant.product_id);
        const category = product?.category_id ? categoryById.get(product.category_id) : undefined;
        return [
          variant.sku_code,
          variant.variant_name,
          product?.name,
          product?.product_type,
          category?.name,
        ]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase("vi")
          .includes(query);
      })
    : variants;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-012</p>
          <h1>Sản phẩm &amp; SKU</h1>
          <p className="muted">
            Product master tập trung: category → product → SKU → quy cách đóng gói.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/suppliers" className="button button-secondary">Nhà cung cấp</Link>
          <Link href="/customers" className="button button-secondary">Khách hàng</Link>
          <form action="/api/auth/logout" method="post">
            <button type="submit" className="button button-secondary">Đăng xuất</button>
          </form>
        </div>
      </header>

      {state.category_saved || state.product_saved || state.sku_saved ? (
        <div className="alert alert-success">Đã lưu product master.</div>
      ) : null}
      {state.error ? (
        <div className="alert alert-error">
          Không thể lưu dữ liệu. Kiểm tra trường bắt buộc, quyền OWNER/ADMIN hoặc mã bị trùng.
        </div>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card"><span>Categories</span><strong>{categories.length}</strong></article>
        <article className="metric-card"><span>Products</span><strong>{products.length}</strong></article>
        <article className="metric-card"><span>SKUs</span><strong>{variants.length}</strong></article>
        <article className="metric-card"><span>Active packaging</span><strong>{packaging.filter((row) => row.is_active).length}</strong></article>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Danh mục SKU</h2>
            <p className="muted">{visibleVariants.length} SKU hiển thị</p>
          </div>
          <form method="get" className="search-form">
            <input name="q" defaultValue={state.q ?? ""} placeholder="Tìm SKU, sản phẩm, loại, category..." />
            <button type="submit" className="button button-secondary">Tìm</button>
          </form>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>SKU</th><th>Sản phẩm</th><th>Category</th><th>Loại</th>
                <th>Kích thước</th><th>Base unit</th><th>Purchase unit</th>
                <th>Packaging</th><th>Min stock</th><th>Trạng thái</th>
              </tr>
            </thead>
            <tbody>
              {visibleVariants.map((variant) => {
                const product = productById.get(variant.product_id);
                const category = product?.category_id ? categoryById.get(product.category_id) : undefined;
                return (
                  <tr key={variant.id}>
                    <td><Link href={`/products/${variant.id}`} className="row-link">{variant.sku_code}</Link></td>
                    <td>{product?.name ?? "—"}{variant.variant_name ? <div className="subtle">{variant.variant_name}</div> : null}</td>
                    <td>{category?.name ?? "—"}</td>
                    <td>{product?.product_type ?? "—"}</td>
                    <td>{variant.capacity_value !== null ? `${compactNumber(variant.capacity_value)} ${variant.capacity_unit ?? ""}`.trim() : "—"}</td>
                    <td>{variant.base_inventory_unit}</td>
                    <td>{variant.default_purchase_unit ?? "—"}</td>
                    <td>{packageCount.get(variant.id) ?? 0}</td>
                    <td>{compactNumber(variant.minimum_stock_quantity)}</td>
                    <td><span className={variant.is_active && product?.is_active ? "status status-active" : "status status-muted"}>{variant.is_active && product?.is_active ? "Active" : "Inactive"}</span></td>
                  </tr>
                );
              })}
              {visibleVariants.length === 0 ? <tr><td colSpan={10} className="empty-state">Chưa có SKU phù hợp.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      {canManage ? (
        <>
          <section className="dashboard-grid">
            <article className="content-card">
              <h2>Tạo category</h2>
              <form action="/api/product-categories" method="post" className="form-stack">
                <div className="form-row">
                  <label>Tên category *<input name="name" required /></label>
                  <label>Mã category<input name="category_code" /></label>
                </div>
                <label>Mô tả<textarea name="description" rows={2} /></label>
                <button className="button button-primary" type="submit">Tạo category</button>
              </form>
            </article>
            <article className="content-card">
              <h2>Tạo product</h2>
              <form action="/api/products" method="post" className="form-stack">
                <div className="form-row">
                  <label>Tên sản phẩm *<input name="name" required /></label>
                  <label>Category
                    <select name="category_id">
                      <option value="">Không phân loại</option>
                      {categories.filter((row) => row.is_active).map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}
                    </select>
                  </label>
                </div>
                <label>Loại sản phẩm / cup type<input name="product_type" placeholder="Ví dụ: printed cup, plain cup, lid..." /></label>
                <label>Mô tả<textarea name="description" rows={2} /></label>
                <button className="button button-primary" type="submit">Tạo product</button>
              </form>
            </article>
          </section>

          <section className="content-card">
            <h2>Tạo SKU / variant</h2>
            <form action="/api/product-variants" method="post" className="form-stack">
              <div className="form-row">
                <label>Product *
                  <select name="product_id" required>
                    <option value="">Chọn product</option>
                    {products.filter((row) => row.is_active).map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}
                  </select>
                </label>
                <label>SKU code *<input name="sku_code" required /></label>
              </div>
              <div className="form-row">
                <label>Tên variant<input name="variant_name" /></label>
                <label>Base inventory unit *<input name="base_inventory_unit" defaultValue="piece" required /></label>
              </div>
              <div className="form-row">
                <label>Capacity / size<input name="capacity_value" type="number" min="0" step="any" /></label>
                <label>Đơn vị capacity<input name="capacity_unit" placeholder="ml, oz, mm..." /></label>
              </div>
              <div className="form-row">
                <label>Default purchase unit<input name="default_purchase_unit" placeholder="carton, box..." /></label>
                <label>Minimum stock<input name="minimum_stock_quantity" type="number" min="0" step="any" defaultValue="0" /></label>
              </div>
              <button className="button button-primary" type="submit">Tạo SKU</button>
            </form>
          </section>

          <section className="content-card">
            <h2>Quản lý category</h2>
            <div className="stack-list">
              {categories.map((category) => (
                <form action={`/api/product-categories/${category.id}`} method="post" className="stack-item" key={category.id}>
                  <div className="inline-fields">
                    <input name="name" defaultValue={category.name} aria-label="Tên category" required />
                    <input name="category_code" defaultValue={category.category_code ?? ""} aria-label="Mã category" />
                    <input name="description" defaultValue={category.description ?? ""} aria-label="Mô tả category" />
                  </div>
                  <div className="inline-actions">
                    <label className="checkbox-row"><input type="checkbox" name="is_active" defaultChecked={category.is_active} /> Active</label>
                    <button className="button button-secondary" type="submit">Lưu</button>
                  </div>
                </form>
              ))}
            </div>
          </section>
        </>
      ) : (
        <section className="content-card">
          <p className="permission-note">Product master là reference data cho mọi vai trò V1; chỉ OWNER/ADMIN được thay đổi category, product, SKU và packaging.</p>
        </section>
      )}

      <section className="content-card">
        <h2>Ranh giới module</h2>
        <p className="muted">
          OPS-012 chỉ quản lý identity, đơn vị cơ sở, minimum stock và packaging conversion.
          Purchase cost / logistics allocation / pricing thuộc OPS-013. Stock on-hand / reserved / available phải tiếp tục được dẫn xuất từ inventory ledger ở các task inventory sau, không chỉnh trực tiếp tại product master.
        </p>
      </section>
    </main>
  );
}

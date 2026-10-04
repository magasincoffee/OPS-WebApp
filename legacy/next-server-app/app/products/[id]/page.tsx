import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Variant = {
  id: string; product_id: string; sku_code: string; variant_name: string | null;
  capacity_value: number | null; capacity_unit: string | null;
  base_inventory_unit: string; default_purchase_unit: string | null;
  minimum_stock_quantity: number; is_active: boolean;
};

type Product = {
  id: string; category_id: string | null; name: string;
  product_type: string | null; description: string | null; is_active: boolean;
};

type Category = { id: string; name: string; is_active: boolean };

type Packaging = {
  id: string; package_code: string; package_name: string; units_per_package: number;
  is_purchase_default: boolean; is_sale_default: boolean;
  effective_from: string; effective_to: string | null; is_active: boolean;
};

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{
    product_saved?: string; sku_saved?: string; packaging_saved?: string; error?: string;
  }>;
};

function num(value: number | null) {
  return value === null ? "" : String(Number(value));
}

export default async function ProductVariantPage({ params, searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const canManage = roles.has("OWNER_ADMIN");
  const { id } = await params;
  const state = await searchParams;
  const encoded = encodeURIComponent(id);

  let variantRows: Variant[];
  try {
    variantRows = await supabaseRest<Variant[]>(
      `product_variants?id=eq.${encoded}&select=id,product_id,sku_code,variant_name,capacity_value,capacity_unit,base_inventory_unit,default_purchase_unit,minimum_stock_quantity,is_active`,
    );
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) redirect("/login?error=session");
    throw error;
  }
  const variant = variantRows[0];
  if (!variant) notFound();

  const [productRows, categories, packaging] = await Promise.all([
    supabaseRest<Product[]>(
      `products?id=eq.${encodeURIComponent(variant.product_id)}&select=id,category_id,name,product_type,description,is_active`,
    ),
    supabaseRest<Category[]>(
      "product_categories?select=id,name,is_active&order=name.asc&limit=300",
    ),
    supabaseRest<Packaging[]>(
      `product_packaging?product_variant_id=eq.${encoded}&select=id,package_code,package_name,units_per_package,is_purchase_default,is_sale_default,effective_from,effective_to,is_active&order=effective_from.desc,package_code.asc&limit=500`,
    ),
  ]);

  const product = productRows[0];
  if (!product) notFound();
  const category = product.category_id ? categories.find((row) => row.id === product.category_id) : undefined;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <Link href="/products" className="text-link">← Product master</Link>
          <p className="eyebrow">PRODUCT / SKU PROFILE</p>
          <h1>{variant.sku_code}</h1>
          <p className="muted">{product.name}{variant.variant_name ? ` · ${variant.variant_name}` : ""}{category ? ` · ${category.name}` : ""}</p>
        </div>
        <form action="/api/auth/logout" method="post">
          <button className="button button-secondary" type="submit">Đăng xuất</button>
        </form>
      </header>

      {state.product_saved || state.sku_saved || state.packaging_saved ? <div className="alert alert-success">Đã lưu product master.</div> : null}
      {state.error ? <div className="alert alert-error">Không thể lưu. Kiểm tra trường bắt buộc, dữ liệu trùng hoặc quyền OWNER/ADMIN.</div> : null}

      <section className="dashboard-grid">
        <article className="content-card">
          <h2>Product</h2>
          {canManage ? (
            <form action={`/api/products/${product.id}`} method="post" className="form-stack">
              <input type="hidden" name="variant_id" value={variant.id} />
              <div className="form-row">
                <label>Tên sản phẩm *<input name="name" defaultValue={product.name} required /></label>
                <label>Category
                  <select name="category_id" defaultValue={product.category_id ?? ""}>
                    <option value="">Không phân loại</option>
                    {categories.map((row) => <option key={row.id} value={row.id}>{row.name}{row.is_active ? "" : " (inactive)"}</option>)}
                  </select>
                </label>
              </div>
              <label>Loại sản phẩm / cup type<input name="product_type" defaultValue={product.product_type ?? ""} /></label>
              <label>Mô tả<textarea name="description" rows={3} defaultValue={product.description ?? ""} /></label>
              <label className="checkbox-row"><input type="checkbox" name="is_active" defaultChecked={product.is_active} /> Product active</label>
              <button className="button button-primary" type="submit">Lưu product</button>
            </form>
          ) : (
            <div className="stack-list">
              <div className="stack-item"><span>Product</span><strong>{product.name}</strong></div>
              <div className="stack-item"><span>Category</span><strong>{category?.name ?? "—"}</strong></div>
              <div className="stack-item"><span>Loại</span><strong>{product.product_type ?? "—"}</strong></div>
              <div className="stack-item"><span>Mô tả</span><strong>{product.description ?? "—"}</strong></div>
            </div>
          )}
        </article>

        <article className="content-card">
          <h2>SKU / variant</h2>
          {canManage ? (
            <form action={`/api/product-variants/${variant.id}`} method="post" className="form-stack">
              <div className="form-row">
                <label>SKU code *<input name="sku_code" defaultValue={variant.sku_code} required /></label>
                <label>Tên variant<input name="variant_name" defaultValue={variant.variant_name ?? ""} /></label>
              </div>
              <div className="form-row">
                <label>Capacity<input name="capacity_value" type="number" min="0" step="any" defaultValue={num(variant.capacity_value)} /></label>
                <label>Capacity unit<input name="capacity_unit" defaultValue={variant.capacity_unit ?? ""} /></label>
              </div>
              <div className="form-row">
                <label>Base inventory unit *<input name="base_inventory_unit" defaultValue={variant.base_inventory_unit} required /></label>
                <label>Default purchase unit<input name="default_purchase_unit" defaultValue={variant.default_purchase_unit ?? ""} /></label>
              </div>
              <label>Minimum stock<input name="minimum_stock_quantity" type="number" min="0" step="any" defaultValue={num(variant.minimum_stock_quantity)} /></label>
              <label className="checkbox-row"><input type="checkbox" name="is_active" defaultChecked={variant.is_active} /> SKU active</label>
              <button className="button button-primary" type="submit">Lưu SKU</button>
            </form>
          ) : (
            <div className="stack-list">
              <div className="stack-item"><span>Base inventory unit</span><strong>{variant.base_inventory_unit}</strong></div>
              <div className="stack-item"><span>Purchase unit</span><strong>{variant.default_purchase_unit ?? "—"}</strong></div>
              <div className="stack-item"><span>Capacity</span><strong>{variant.capacity_value ?? "—"} {variant.capacity_unit ?? ""}</strong></div>
              <div className="stack-item"><span>Minimum stock</span><strong>{variant.minimum_stock_quantity}</strong></div>
            </div>
          )}
        </article>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Packaging conversion</h2>
            <p className="muted">Mỗi quy cách quy đổi về base unit <strong>{variant.base_inventory_unit}</strong>.</p>
          </div>
        </div>

        <div className="table-wrap">
          <table>
            <thead><tr><th>Mã</th><th>Tên</th><th>Quy đổi</th><th>Mặc định mua</th><th>Mặc định bán</th><th>Hiệu lực</th><th>Trạng thái</th></tr></thead>
            <tbody>
              {packaging.map((row) => (
                <tr key={row.id}>
                  <td>{row.package_code}</td><td>{row.package_name}</td>
                  <td>1 {row.package_name} = {row.units_per_package} {variant.base_inventory_unit}</td>
                  <td>{row.is_purchase_default ? "Có" : "—"}</td>
                  <td>{row.is_sale_default ? "Có" : "—"}</td>
                  <td>{row.effective_from}{row.effective_to ? ` → ${row.effective_to}` : " →"}</td>
                  <td>{row.is_active ? "Active" : "Inactive"}</td>
                </tr>
              ))}
              {packaging.length === 0 ? <tr><td colSpan={7} className="empty-state">Chưa có packaging conversion.</td></tr> : null}
            </tbody>
          </table>
        </div>

        {canManage ? (
          <>
            <h3>Thêm packaging</h3>
            <form action={`/api/product-variants/${variant.id}/packaging`} method="post" className="form-stack">
              <div className="form-row">
                <label>Package code *<input name="package_code" required /></label>
                <label>Package name *<input name="package_name" required placeholder="carton, box, bag..." /></label>
              </div>
              <div className="form-row">
                <label>Units per package *<input name="units_per_package" type="number" min="0.000001" step="any" required /></label>
                <label>Effective from *<input name="effective_from" type="date" defaultValue={new Date().toISOString().slice(0, 10)} required /></label>
              </div>
              <div className="form-row">
                <label>Effective to<input name="effective_to" type="date" /></label>
                <div className="inline-actions">
                  <label className="checkbox-row"><input type="checkbox" name="is_purchase_default" /> Purchase default</label>
                  <label className="checkbox-row"><input type="checkbox" name="is_sale_default" /> Sale default</label>
                </div>
              </div>
              <button className="button button-primary" type="submit">Thêm packaging</button>
            </form>

            {packaging.length > 0 ? (
              <>
                <h3>Cập nhật packaging</h3>
                <div className="stack-list">
                  {packaging.map((row) => (
                    <form action={`/api/product-packaging/${row.id}`} method="post" className="form-stack package-editor" key={row.id}>
                      <input type="hidden" name="variant_id" value={variant.id} />
                      <div className="form-row">
                        <label>Code<input name="package_code" defaultValue={row.package_code} required /></label>
                        <label>Name<input name="package_name" defaultValue={row.package_name} required /></label>
                      </div>
                      <div className="form-row">
                        <label>Units/package<input name="units_per_package" type="number" min="0.000001" step="any" defaultValue={num(row.units_per_package)} required /></label>
                        <label>Effective from<input name="effective_from" type="date" defaultValue={row.effective_from} required /></label>
                      </div>
                      <div className="form-row">
                        <label>Effective to<input name="effective_to" type="date" defaultValue={row.effective_to ?? ""} /></label>
                        <div className="inline-actions">
                          <label className="checkbox-row"><input type="checkbox" name="is_purchase_default" defaultChecked={row.is_purchase_default} /> Purchase default</label>
                          <label className="checkbox-row"><input type="checkbox" name="is_sale_default" defaultChecked={row.is_sale_default} /> Sale default</label>
                          <label className="checkbox-row"><input type="checkbox" name="is_active" defaultChecked={row.is_active} /> Active</label>
                        </div>
                      </div>
                      <button className="button button-secondary" type="submit">Lưu packaging</button>
                    </form>
                  ))}
                </div>
              </>
            ) : null}
          </>
        ) : null}
      </section>

      <section className="content-card">
        <h2>Inventory truth</h2>
        <p className="muted">
          Base unit và minimum stock được quản lý tại SKU. On-hand, reserved và available không được sửa tại đây:
          chúng phải được dẫn xuất từ inventory ledger theo SOT.
        </p>
      </section>
    </main>
  );
}

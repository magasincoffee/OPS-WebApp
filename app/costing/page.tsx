import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import {
  getAccessToken,
  SupabaseRestError,
  supabaseRest,
} from "@/lib/supabase/rest";

type Product = {
  id: string;
  name: string;
  product_type: string | null;
};

type Variant = {
  id: string;
  product_id: string;
  sku_code: string;
  variant_name: string | null;
  base_inventory_unit: string;
};

type Packaging = {
  id: string;
  product_variant_id: string;
  package_name: string;
  units_per_package: number;
  is_active: boolean;
};

type Supplier = {
  id: string;
  supplier_name: string;
};

type CostHistory = {
  id: string;
  product_variant_id: string;
  supplier_id: string | null;
  packaging_id: string | null;
  effective_at: string;
  purchase_unit: string;
  units_per_purchase_unit: number;
  purchase_price_per_purchase_unit: number;
  freight_cost_per_purchase_unit: number;
  other_allocated_cost_per_purchase_unit: number;
  purchase_cost_per_base_unit: number;
  landed_cost_per_base_unit: number;
  inventory_cost_basis_per_base_unit: number | null;
  currency_code: string;
  source_reference: string | null;
  notes: string | null;
};

type PricingRule = {
  id: string;
  name: string;
  product_variant_id: string | null;
  product_type: string | null;
  print_mode: "ANY" | "PRINTED" | "PLAIN";
  min_print_colors: number | null;
  max_print_colors: number | null;
  currency_code: string;
  priority: number;
  effective_from: string;
  effective_to: string | null;
  is_active: boolean;
};

type PriceTier = {
  id: string;
  pricing_rule_id: string;
  min_quantity_base_units: number;
  max_quantity_base_units: number | null;
  fixed_selling_price_per_base_unit: number | null;
  markup_percent: number | null;
  margin_percent: number | null;
  print_cost_per_base_unit: number;
};

type PageProps = {
  searchParams: Promise<{
    cost_saved?: string;
    rule_saved?: string;
    tier_saved?: string;
    error?: string;
  }>;
};

function money(value: number, currency = "VND") {
  try {
    return new Intl.NumberFormat("vi-VN", {
      style: "currency",
      currency,
      maximumFractionDigits: currency === "VND" ? 0 : 4,
    }).format(Number(value));
  } catch {
    return `${Number(value).toLocaleString("vi-VN")} ${currency}`;
  }
}

function number(value: number | null) {
  if (value === null) return "—";
  return new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 6 }).format(Number(value));
}

function dateTime(value: string) {
  return new Intl.DateTimeFormat("vi-VN", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function tierBasis(tier: PriceTier) {
  if (tier.fixed_selling_price_per_base_unit !== null) {
    return { code: "FIXED", value: tier.fixed_selling_price_per_base_unit, label: "Fixed selling price" };
  }
  if (tier.markup_percent !== null) {
    return { code: "MARKUP", value: tier.markup_percent, label: "Markup %" };
  }
  return { code: "MARGIN", value: tier.margin_percent ?? 0, label: "Margin %" };
}

export default async function CostingPage({ searchParams }: PageProps) {
  const accessToken = await getAccessToken();
  if (!accessToken) redirect("/login");

  const roles = await getCurrentRoles();
  const isOwner = roles.has("OWNER_ADMIN");
  const isAccounting = roles.has("ACCOUNTING");
  const isSales = roles.has("SALES");
  const canViewCost = isOwner || isAccounting;
  const canViewPricing = isOwner || isAccounting || isSales;
  const state = await searchParams;

  let products: Product[];
  let variants: Variant[];
  let packaging: Packaging[];

  try {
    [products, variants, packaging] = await Promise.all([
      supabaseRest<Product[]>(
        "products?select=id,name,product_type&order=name.asc&limit=1000",
      ),
      supabaseRest<Variant[]>(
        "product_variants?select=id,product_id,sku_code,variant_name,base_inventory_unit&order=sku_code.asc&limit=2000",
      ),
      supabaseRest<Packaging[]>(
        "product_packaging?select=id,product_variant_id,package_name,units_per_package,is_active&is_active=eq.true&order=package_name.asc&limit=5000",
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
  const productTypes = [...new Set(products.map((row) => row.product_type).filter((value): value is string => Boolean(value)))].sort();

  let suppliers: Supplier[] = [];
  let costs: CostHistory[] = [];
  if (canViewCost) {
    [suppliers, costs] = await Promise.all([
      supabaseRest<Supplier[]>(
        "suppliers?select=id,supplier_name&order=supplier_name.asc&limit=1000",
      ),
      supabaseRest<CostHistory[]>(
        "purchase_cost_history?select=id,product_variant_id,supplier_id,packaging_id,effective_at,purchase_unit,units_per_purchase_unit,purchase_price_per_purchase_unit,freight_cost_per_purchase_unit,other_allocated_cost_per_purchase_unit,purchase_cost_per_base_unit,landed_cost_per_base_unit,inventory_cost_basis_per_base_unit,currency_code,source_reference,notes&order=effective_at.desc&limit=2000",
      ),
    ]);
  }

  let rules: PricingRule[] = [];
  let tiers: PriceTier[] = [];
  if (canViewPricing) {
    [rules, tiers] = await Promise.all([
      supabaseRest<PricingRule[]>(
        "pricing_rules?select=id,name,product_variant_id,product_type,print_mode,min_print_colors,max_print_colors,currency_code,priority,effective_from,effective_to,is_active&order=priority.asc,effective_from.desc,name.asc&limit=1000",
      ),
      supabaseRest<PriceTier[]>(
        "price_tiers?select=id,pricing_rule_id,min_quantity_base_units,max_quantity_base_units,fixed_selling_price_per_base_unit,markup_percent,margin_percent,print_cost_per_base_unit&order=min_quantity_base_units.asc&limit=5000",
      ),
    ]);
  }

  const supplierById = new Map(suppliers.map((row) => [row.id, row]));
  const latestCostByVariant = new Map<string, CostHistory>();
  for (const row of costs) {
    if (!latestCostByVariant.has(row.product_variant_id)) latestCostByVariant.set(row.product_variant_id, row);
  }
  const tiersByRule = new Map<string, PriceTier[]>();
  for (const tier of tiers) {
    const list = tiersByRule.get(tier.pricing_rule_id) ?? [];
    list.push(tier);
    tiersByRule.set(tier.pricing_rule_id, list);
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-013</p>
          <h1>Giá vốn &amp; Pricing</h1>
          <p className="muted">
            Lịch sử giá mua, logistics/landed cost và quantity-based pricing rules.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/products" className="button button-secondary">Sản phẩm &amp; SKU</Link>
          <Link href="/suppliers" className="button button-secondary">Nhà cung cấp</Link>
          <form action="/api/auth/logout" method="post">
            <button className="button button-secondary" type="submit">Đăng xuất</button>
          </form>
        </div>
      </header>

      {state.cost_saved || state.rule_saved || state.tier_saved ? (
        <div className="alert alert-success">Đã lưu dữ liệu cost/pricing.</div>
      ) : null}
      {state.error ? (
        <div className="alert alert-error">
          Không thể lưu dữ liệu. Kiểm tra trường bắt buộc, phạm vi số liệu, quy tắc pricing hoặc quyền OWNER/ADMIN.
        </div>
      ) : null}

      {!canViewPricing && !canViewCost ? (
        <section className="content-card">
          <h2>Không có quyền tài chính/pricing</h2>
          <p className="permission-note">
            WAREHOUSE và PRINTER/PRODUCTION không được truy cập cost/profitability theo SOT.
            Product identity vẫn có tại Product master.
          </p>
        </section>
      ) : null}

      {canViewCost ? (
        <>
          <section className="metric-grid">
            <article className="metric-card"><span>Cost history</span><strong>{costs.length}</strong></article>
            <article className="metric-card"><span>SKU có cost</span><strong>{latestCostByVariant.size}</strong></article>
            <article className="metric-card"><span>Pricing rules</span><strong>{rules.length}</strong></article>
            <article className="metric-card"><span>Quantity tiers</span><strong>{tiers.length}</strong></article>
          </section>

          <section className="content-card">
            <div className="section-heading">
              <div>
                <h2>Latest cost theo SKU</h2>
                <p className="muted">Cost được lấy từ record có effective_at mới nhất; không ghi đè lịch sử.</p>
              </div>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>SKU</th><th>Supplier</th><th>Giá mua</th><th>Freight + khác</th>
                    <th>Purchase/base</th><th>Landed/base</th><th>Package cost</th><th>Hiệu lực</th>
                  </tr>
                </thead>
                <tbody>
                  {[...latestCostByVariant.values()].map((row) => {
                    const variant = variantById.get(row.product_variant_id);
                    const product = variant ? productById.get(variant.product_id) : undefined;
                    const packages = packaging.filter((item) => item.product_variant_id === row.product_variant_id);
                    return (
                      <tr key={row.id}>
                        <td>
                          <strong>{variant?.sku_code ?? "—"}</strong>
                          <div className="subtle">{product?.name ?? "—"}</div>
                        </td>
                        <td>{row.supplier_id ? supplierById.get(row.supplier_id)?.supplier_name ?? "—" : "—"}</td>
                        <td>{money(row.purchase_price_per_purchase_unit, row.currency_code)} / {row.purchase_unit}</td>
                        <td>{money(Number(row.freight_cost_per_purchase_unit) + Number(row.other_allocated_cost_per_purchase_unit), row.currency_code)}</td>
                        <td>{money(row.purchase_cost_per_base_unit, row.currency_code)}</td>
                        <td>{money(row.landed_cost_per_base_unit, row.currency_code)}</td>
                        <td>
                          {packages.length === 0 ? "—" : packages.slice(0, 4).map((item) => (
                            <div key={item.id} className="subtle">
                              {item.package_name}: {money(Number(row.landed_cost_per_base_unit) * Number(item.units_per_package), row.currency_code)}
                            </div>
                          ))}
                        </td>
                        <td>{dateTime(row.effective_at)}</td>
                      </tr>
                    );
                  })}
                  {latestCostByVariant.size === 0 ? <tr><td colSpan={8} className="empty-state">Chưa có lịch sử cost.</td></tr> : null}
                </tbody>
              </table>
            </div>
          </section>

          <section className="content-card">
            <h2>Historical cost traceability</h2>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>Thời điểm</th><th>SKU</th><th>Purchase input</th><th>Landed/base</th><th>Inventory basis</th><th>Nguồn</th></tr>
                </thead>
                <tbody>
                  {costs.slice(0, 250).map((row) => (
                    <tr key={row.id}>
                      <td>{dateTime(row.effective_at)}</td>
                      <td>{variantById.get(row.product_variant_id)?.sku_code ?? "—"}</td>
                      <td>
                        {money(row.purchase_price_per_purchase_unit, row.currency_code)} / {row.purchase_unit}
                        <div className="subtle">{number(row.units_per_purchase_unit)} base units</div>
                      </td>
                      <td>{money(row.landed_cost_per_base_unit, row.currency_code)}</td>
                      <td>{row.inventory_cost_basis_per_base_unit === null ? "—" : money(row.inventory_cost_basis_per_base_unit, row.currency_code)}</td>
                      <td>{row.source_reference ?? "—"}{row.notes ? <div className="subtle">{row.notes}</div> : null}</td>
                    </tr>
                  ))}
                  {costs.length === 0 ? <tr><td colSpan={6} className="empty-state">Chưa có cost history.</td></tr> : null}
                </tbody>
              </table>
            </div>
          </section>
        </>
      ) : null}

      {isOwner ? (
        <section className="content-card">
          <h2>Ghi nhận cost mới</h2>
          <p className="muted">Tạo record lịch sử mới; generated purchase/base và landed/base do database tính từ input.</p>
          <form action="/api/costing/cost-history" method="post" className="form-stack">
            <div className="form-row">
              <label>SKU *
                <select name="product_variant_id" required>
                  <option value="">Chọn SKU</option>
                  {variants.map((variant) => <option key={variant.id} value={variant.id}>{variant.sku_code} · {productById.get(variant.product_id)?.name ?? ""}</option>)}
                </select>
              </label>
              <label>Supplier
                <select name="supplier_id">
                  <option value="">Không gắn supplier</option>
                  {suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.supplier_name}</option>)}
                </select>
              </label>
            </div>
            <div className="form-row">
              <label>Packaging reference
                <select name="packaging_id">
                  <option value="">Không gắn packaging</option>
                  {packaging.map((item) => <option key={item.id} value={item.id}>{variantById.get(item.product_variant_id)?.sku_code ?? "SKU"} · {item.package_name} ({number(item.units_per_package)})</option>)}
                </select>
              </label>
              <label>Effective at<input type="datetime-local" name="effective_at" /></label>
            </div>
            <div className="form-row">
              <label>Purchase unit *<input name="purchase_unit" placeholder="carton, box..." required /></label>
              <label>Units / purchase unit *<input type="number" step="any" min="0.000001" name="units_per_purchase_unit" required /></label>
            </div>
            <div className="form-row">
              <label>Purchase price / purchase unit *<input type="number" step="any" min="0" name="purchase_price_per_purchase_unit" required /></label>
              <label>Freight / purchase unit<input type="number" step="any" min="0" name="freight_cost_per_purchase_unit" defaultValue="0" /></label>
            </div>
            <div className="form-row">
              <label>Other allocated cost / purchase unit<input type="number" step="any" min="0" name="other_allocated_cost_per_purchase_unit" defaultValue="0" /></label>
              <label>Inventory cost basis / base unit<input type="number" step="any" min="0" name="inventory_cost_basis_per_base_unit" /></label>
            </div>
            <div className="form-row">
              <label>Currency<input name="currency_code" defaultValue="VND" pattern="[A-Za-z]{3}" required /></label>
              <label>Source reference<input name="source_reference" placeholder="PO, receipt, invoice..." /></label>
            </div>
            <label>Notes<textarea name="notes" rows={2} /></label>
            <button className="button button-primary" type="submit">Ghi nhận cost history</button>
          </form>
        </section>
      ) : null}

      {canViewPricing ? (
        <section className="content-card">
          <div className="section-heading">
            <div>
              <h2>Pricing rules &amp; quantity tiers</h2>
              <p className="muted">Rules có thể target SKU hoặc product type, tách print mode/colors và dùng fixed price, markup hoặc margin.</p>
            </div>
          </div>

          <div className="stack-list">
            {rules.map((rule) => {
              const variant = rule.product_variant_id ? variantById.get(rule.product_variant_id) : undefined;
              const ruleTiers = tiersByRule.get(rule.id) ?? [];
              return (
                <article key={rule.id} className="package-editor">
                  <div className="section-heading">
                    <div>
                      <strong>{rule.name}</strong>
                      <div className="subtle">
                        {variant ? `SKU ${variant.sku_code}` : rule.product_type ? `Type: ${rule.product_type}` : "All products"}
                        {" · "}{rule.print_mode}
                        {" · priority "}{rule.priority}
                        {" · "}{rule.is_active ? "Active" : "Inactive"}
                      </div>
                      <div className="subtle">
                        Hiệu lực {rule.effective_from}{rule.effective_to ? ` → ${rule.effective_to}` : " →"}
                        {rule.min_print_colors !== null || rule.max_print_colors !== null ? ` · colors ${rule.min_print_colors ?? 0}–${rule.max_print_colors ?? "∞"}` : ""}
                      </div>
                    </div>
                  </div>

                  <div className="table-wrap">
                    <table>
                      <thead><tr><th>Quantity base units</th><th>Pricing basis</th><th>Print cost/base</th><th>Currency</th></tr></thead>
                      <tbody>
                        {ruleTiers.map((tier) => {
                          const basis = tierBasis(tier);
                          const salesSafe = isSales && !isOwner && !isAccounting;
                          return (
                            <tr key={tier.id}>
                              <td>{number(tier.min_quantity_base_units)} → {tier.max_quantity_base_units === null ? "∞" : number(tier.max_quantity_base_units)}</td>
                              <td>
                                {salesSafe
                                  ? tier.fixed_selling_price_per_base_unit !== null
                                    ? money(tier.fixed_selling_price_per_base_unit, rule.currency_code)
                                    : "Giá động theo pricing rule"
                                  : basis.code === "FIXED"
                                    ? money(basis.value, rule.currency_code)
                                    : `${basis.label}: ${number(basis.value)}`}
                              </td>
                              <td>{salesSafe ? "—" : money(tier.print_cost_per_base_unit, rule.currency_code)}</td>
                              <td>{rule.currency_code}</td>
                            </tr>
                          );
                        })}
                        {ruleTiers.length === 0 ? <tr><td colSpan={4} className="empty-state">Chưa có quantity tier.</td></tr> : null}
                      </tbody>
                    </table>
                  </div>

                  {isOwner ? (
                    <>
                      <form action={`/api/costing/pricing-rules/${rule.id}`} method="post" className="form-stack">
                        <h3>Cập nhật rule</h3>
                        <div className="form-row">
                          <label>Tên rule<input name="name" defaultValue={rule.name} required /></label>
                          <label>SKU target
                            <select name="product_variant_id" defaultValue={rule.product_variant_id ?? ""}>
                              <option value="">Không cố định SKU</option>
                              {variants.map((item) => <option key={item.id} value={item.id}>{item.sku_code}</option>)}
                            </select>
                          </label>
                        </div>
                        <div className="form-row">
                          <label>Product type<input name="product_type" defaultValue={rule.product_type ?? ""} list="product-types" /></label>
                          <label>Print mode
                            <select name="print_mode" defaultValue={rule.print_mode}>
                              <option value="ANY">ANY</option><option value="PRINTED">PRINTED</option><option value="PLAIN">PLAIN</option>
                            </select>
                          </label>
                        </div>
                        <div className="form-row">
                          <label>Min print colors<input type="number" min="0" step="1" name="min_print_colors" defaultValue={rule.min_print_colors ?? ""} /></label>
                          <label>Max print colors<input type="number" min="0" step="1" name="max_print_colors" defaultValue={rule.max_print_colors ?? ""} /></label>
                        </div>
                        <div className="form-row">
                          <label>Currency<input name="currency_code" defaultValue={rule.currency_code} pattern="[A-Za-z]{3}" required /></label>
                          <label>Priority<input type="number" step="1" name="priority" defaultValue={rule.priority} required /></label>
                        </div>
                        <div className="form-row">
                          <label>Effective from<input type="date" name="effective_from" defaultValue={rule.effective_from} required /></label>
                          <label>Effective to<input type="date" name="effective_to" defaultValue={rule.effective_to ?? ""} /></label>
                        </div>
                        <label className="checkbox-row"><input type="checkbox" name="is_active" defaultChecked={rule.is_active} /> Active</label>
                        <button className="button button-secondary" type="submit">Lưu rule</button>
                      </form>

                      <form action={`/api/costing/pricing-rules/${rule.id}/tiers`} method="post" className="form-stack">
                        <h3>Thêm quantity tier</h3>
                        <div className="form-row">
                          <label>Min quantity *<input type="number" step="any" min="0.000001" name="min_quantity_base_units" required /></label>
                          <label>Max quantity<input type="number" step="any" min="0.000001" name="max_quantity_base_units" /></label>
                        </div>
                        <div className="form-row">
                          <label>Pricing basis
                            <select name="pricing_basis" defaultValue="FIXED">
                              <option value="FIXED">Fixed selling price/base</option>
                              <option value="MARKUP">Markup %</option>
                              <option value="MARGIN">Margin %</option>
                            </select>
                          </label>
                          <label>Basis value *<input type="number" step="any" min="0" name="pricing_basis_value" required /></label>
                        </div>
                        <label>Print cost / base unit<input type="number" step="any" min="0" name="print_cost_per_base_unit" defaultValue="0" /></label>
                        <button className="button button-primary" type="submit">Thêm tier</button>
                      </form>

                      {ruleTiers.map((tier) => {
                        const basis = tierBasis(tier);
                        return (
                          <form action={`/api/costing/price-tiers/${tier.id}`} method="post" className="form-stack package-editor" key={`edit-${tier.id}`}>
                            <h3>Sửa tier từ {number(tier.min_quantity_base_units)}</h3>
                            <div className="form-row">
                              <label>Min quantity<input type="number" step="any" min="0.000001" name="min_quantity_base_units" defaultValue={tier.min_quantity_base_units} required /></label>
                              <label>Max quantity<input type="number" step="any" min="0.000001" name="max_quantity_base_units" defaultValue={tier.max_quantity_base_units ?? ""} /></label>
                            </div>
                            <div className="form-row">
                              <label>Pricing basis
                                <select name="pricing_basis" defaultValue={basis.code}>
                                  <option value="FIXED">Fixed selling price/base</option>
                                  <option value="MARKUP">Markup %</option>
                                  <option value="MARGIN">Margin %</option>
                                </select>
                              </label>
                              <label>Basis value<input type="number" step="any" min="0" name="pricing_basis_value" defaultValue={basis.value} required /></label>
                            </div>
                            <label>Print cost / base unit<input type="number" step="any" min="0" name="print_cost_per_base_unit" defaultValue={tier.print_cost_per_base_unit} /></label>
                            <button className="button button-secondary" type="submit">Lưu tier</button>
                          </form>
                        );
                      })}
                    </>
                  ) : null}
                </article>
              );
            })}
            {rules.length === 0 ? <p className="empty-state">Chưa có pricing rule.</p> : null}
          </div>
        </section>
      ) : null}

      {isOwner ? (
        <section className="content-card">
          <h2>Tạo pricing rule</h2>
          <form action="/api/costing/pricing-rules" method="post" className="form-stack">
            <div className="form-row">
              <label>Tên rule *<input name="name" required /></label>
              <label>SKU target
                <select name="product_variant_id">
                  <option value="">Không cố định SKU</option>
                  {variants.map((variant) => <option key={variant.id} value={variant.id}>{variant.sku_code}</option>)}
                </select>
              </label>
            </div>
            <div className="form-row">
              <label>Product type<input name="product_type" list="product-types" /></label>
              <label>Print mode
                <select name="print_mode" defaultValue="ANY">
                  <option value="ANY">ANY</option><option value="PRINTED">PRINTED</option><option value="PLAIN">PLAIN</option>
                </select>
              </label>
            </div>
            <div className="form-row">
              <label>Min print colors<input type="number" min="0" step="1" name="min_print_colors" /></label>
              <label>Max print colors<input type="number" min="0" step="1" name="max_print_colors" /></label>
            </div>
            <div className="form-row">
              <label>Currency<input name="currency_code" defaultValue="VND" pattern="[A-Za-z]{3}" required /></label>
              <label>Priority<input type="number" step="1" name="priority" defaultValue="100" required /></label>
            </div>
            <div className="form-row">
              <label>Effective from<input type="date" name="effective_from" defaultValue={new Date().toISOString().slice(0, 10)} required /></label>
              <label>Effective to<input type="date" name="effective_to" /></label>
            </div>
            <button className="button button-primary" type="submit">Tạo pricing rule</button>
          </form>
          <datalist id="product-types">
            {productTypes.map((type) => <option key={type} value={type} />)}
          </datalist>
        </section>
      ) : null}

      <section className="content-card">
        <h2>Ranh giới workflow</h2>
        <p className="muted">
          OPS-013 quản lý cost history và pricing configuration. Purchase orders/goods receipts sẽ cung cấp transaction data ở OPS-020/OPS-021;
          quotations áp dụng pricing rules ở OPS-030. Cost history hiện được thêm theo kiểu append để giữ traceability.
        </p>
      </section>
    </main>
  );
}

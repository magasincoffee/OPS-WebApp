import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Quotation = {
  id: string;
  quotation_number: string;
  customer_id: string;
  status: string;
  quotation_date: string;
  valid_until: string | null;
  currency_code: string;
  sent_at: string | null;
  accepted_at: string | null;
  rejected_at: string | null;
  expired_at: string | null;
  notes: string | null;
};

type Customer = { id: string; display_name: string; customer_code: string | null };
type Product = { id: string; name: string; product_type: string | null };
type Variant = {
  id: string;
  product_id: string;
  sku_code: string;
  variant_name: string | null;
  base_inventory_unit: string;
  is_active: boolean;
};
type Packaging = {
  id: string;
  product_variant_id: string;
  package_code: string;
  package_name: string;
  units_per_package: number;
  is_active: boolean;
  effective_from: string;
  effective_to: string | null;
};
type Item = {
  id: string;
  quotation_id: string;
  product_variant_id: string;
  packaging_id: string | null;
  sale_unit: string;
  sale_quantity: number;
  units_per_sale_unit: number;
  base_quantity: number;
  unit_price_per_sale_unit: number;
  discount_amount: number;
  print_mode: string;
  print_color_count: number | null;
  print_specification: string | null;
  artwork_reference: string | null;
  requested_due_date: string | null;
  line_subtotal: number;
  line_total: number;
  notes: string | null;
  pricing_rule_id: string | null;
  price_tier_id: string | null;
};
type Total = {
  quotation_id: string;
  subtotal_amount: number;
  discount_amount: number;
  total_amount: number;
  currency_code: string;
};
type PricingRule = { id: string; name: string };

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ action?: string; error?: string }>;
};

function money(value: number, currency: string) {
  return new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency,
    maximumFractionDigits: currency === "VND" ? 0 : 2,
  }).format(Number(value));
}

function num(value: number) {
  return new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 6 }).format(Number(value));
}

function date(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("vi-VN", { dateStyle: "short" }).format(
    new Date(`${value}T00:00:00`),
  );
}

export default async function QuotationDetailPage({ params, searchParams }: PageProps) {
  const roles = await getCurrentRoles();
  const canUse = roles.has("OWNER_ADMIN") || roles.has("SALES");
  if (!canUse) redirect("/quotations");

  const { id } = await params;
  const state = await searchParams;

  let quotations: Quotation[];
  let customers: Customer[];
  let products: Product[];
  let variants: Variant[];
  let packaging: Packaging[];
  let items: Item[];
  let totals: Total[];
  let rules: PricingRule[];

  try {
    [quotations, customers, products, variants, packaging, items, totals, rules] = await Promise.all([
      supabaseRest<Quotation[]>(
        `quotations?id=eq.${encodeURIComponent(id)}&select=id,quotation_number,customer_id,status,quotation_date,valid_until,currency_code,sent_at,accepted_at,rejected_at,expired_at,notes`,
      ),
      supabaseRest<Customer[]>("customers?select=id,display_name,customer_code&limit=2000"),
      supabaseRest<Product[]>("products?select=id,name,product_type&limit=2000"),
      supabaseRest<Variant[]>(
        "product_variants?select=id,product_id,sku_code,variant_name,base_inventory_unit,is_active&is_active=eq.true&order=sku_code.asc&limit=5000",
      ),
      supabaseRest<Packaging[]>(
        "product_packaging?select=id,product_variant_id,package_code,package_name,units_per_package,is_active,effective_from,effective_to&is_active=eq.true&order=package_name.asc&limit=5000",
      ),
      supabaseRest<Item[]>(
        `quotation_items?quotation_id=eq.${encodeURIComponent(id)}&select=id,quotation_id,product_variant_id,packaging_id,sale_unit,sale_quantity,units_per_sale_unit,base_quantity,unit_price_per_sale_unit,discount_amount,print_mode,print_color_count,print_specification,artwork_reference,requested_due_date,line_subtotal,line_total,notes,pricing_rule_id,price_tier_id&order=created_at.asc&limit=500`,
      ),
      supabaseRest<Total[]>(
        `quotation_totals?quotation_id=eq.${encodeURIComponent(id)}&select=quotation_id,subtotal_amount,discount_amount,total_amount,currency_code`,
      ),
      supabaseRest<PricingRule[]>("pricing_rules?select=id,name&limit=2000"),
    ]);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) redirect("/login?error=session");
    throw error;
  }

  const quotation = quotations[0];
  if (!quotation) notFound();

  const customerById = new Map(customers.map((row) => [row.id, row]));
  const productById = new Map(products.map((row) => [row.id, row]));
  const variantById = new Map(variants.map((row) => [row.id, row]));
  const ruleById = new Map(rules.map((row) => [row.id, row]));
  const total = totals[0] ?? {
    quotation_id: quotation.id,
    subtotal_amount: 0,
    discount_amount: 0,
    total_amount: 0,
    currency_code: quotation.currency_code,
  };

  const packagingByVariant = new Map<string, Packaging[]>();
  for (const row of packaging) {
    const group = packagingByVariant.get(row.product_variant_id) ?? [];
    group.push(row);
    packagingByVariant.set(row.product_variant_id, group);
  }

  const canExpire =
    quotation.status === "SENT" &&
    quotation.valid_until !== null &&
    quotation.valid_until < new Date().toISOString().slice(0, 10);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-030</p>
          <h1>{quotation.quotation_number}</h1>
          <p className="muted">
            {customerById.get(quotation.customer_id)?.display_name ?? "Customer"} · {quotation.status} · valid until {date(quotation.valid_until)}
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/quotations" className="button button-secondary">Quotations</Link>
          <Link href="/costing" className="button button-secondary">Pricing rules</Link>
        </div>
      </header>

      {state.action ? (
        <section className="content-card"><p className="permission-note">Quotation action completed: {state.action}.</p></section>
      ) : null}
      {state.error ? (
        <section className="content-card">
          <p className="permission-note">
            Không thể hoàn tất thao tác ({state.error}). Kiểm tra pricing rule/tier, quantity, print mode, validity và trạng thái quotation.
          </p>
        </section>
      ) : null}

      <section className="metric-grid">
        <article className="metric-card"><span>Status</span><strong>{quotation.status}</strong></article>
        <article className="metric-card"><span>Subtotal</span><strong className="metric-small">{money(total.subtotal_amount, total.currency_code)}</strong></article>
        <article className="metric-card"><span>Discount</span><strong className="metric-small">{money(total.discount_amount, total.currency_code)}</strong></article>
        <article className="metric-card"><span>Total</span><strong className="metric-small">{money(total.total_amount, total.currency_code)}</strong></article>
      </section>

      <section className="content-card">
        <div className="section-heading">
          <div>
            <h2>Lifecycle</h2>
            <p className="muted">Line items bị khóa sau khi báo giá được gửi.</p>
          </div>
          <div className="hero-actions">
            {quotation.status === "DRAFT" && items.length > 0 ? (
              <form action="/api/quotations/operations" method="post">
                <input type="hidden" name="operation" value="status" />
                <input type="hidden" name="quotation_id" value={quotation.id} />
                <input type="hidden" name="status" value="SENT" />
                <button type="submit" className="button button-primary">Gửi báo giá</button>
              </form>
            ) : null}
            {quotation.status === "SENT" ? (
              <>
                <form action="/api/quotations/operations" method="post">
                  <input type="hidden" name="operation" value="status" />
                  <input type="hidden" name="quotation_id" value={quotation.id} />
                  <input type="hidden" name="status" value="ACCEPTED" />
                  <button type="submit" className="button button-primary">Khách chấp nhận</button>
                </form>
                <form action="/api/quotations/operations" method="post">
                  <input type="hidden" name="operation" value="status" />
                  <input type="hidden" name="quotation_id" value={quotation.id} />
                  <input type="hidden" name="status" value="REJECTED" />
                  <button type="submit" className="button button-secondary">Khách từ chối</button>
                </form>
                {canExpire ? (
                  <form action="/api/quotations/operations" method="post">
                    <input type="hidden" name="operation" value="status" />
                    <input type="hidden" name="quotation_id" value={quotation.id} />
                    <input type="hidden" name="status" value="EXPIRED" />
                    <button type="submit" className="button button-secondary">Đánh dấu hết hạn</button>
                  </form>
                ) : null}
              </>
            ) : null}
          </div>
        </div>
        <p className="muted">
          ACCEPTED là trạng thái sẵn sàng chuyển thành Sales Order. Việc tạo Sales Order thuộc OPS-031 và không được thực hiện trong task này.
        </p>
      </section>

      <section className="content-card">
        <h2>Quotation lines</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>SKU</th><th>Qty</th><th>Print</th><th>Unit price</th><th>Discount</th><th>Total</th><th>Pricing</th><th></th></tr>
            </thead>
            <tbody>
              {items.map((item) => {
                const variant = variantById.get(item.product_variant_id);
                return (
                  <tr key={item.id}>
                    <td>
                      <strong>{variant?.sku_code ?? item.product_variant_id}</strong>
                      <div className="subtle">{productById.get(variant?.product_id ?? "")?.name ?? ""}</div>
                    </td>
                    <td>{num(item.sale_quantity)} {item.sale_unit}<div className="subtle">{num(item.base_quantity)} base units</div></td>
                    <td>
                      {item.print_mode}
                      {item.print_color_count ? <div className="subtle">{item.print_color_count} color(s)</div> : null}
                      {item.print_specification ? <div className="subtle">{item.print_specification}</div> : null}
                    </td>
                    <td>{money(item.unit_price_per_sale_unit, quotation.currency_code)}</td>
                    <td>{money(item.discount_amount, quotation.currency_code)}</td>
                    <td>{money(item.line_total, quotation.currency_code)}</td>
                    <td>{item.pricing_rule_id ? ruleById.get(item.pricing_rule_id)?.name ?? "Pricing rule" : "—"}</td>
                    <td>
                      {quotation.status === "DRAFT" ? (
                        <form action="/api/quotations/operations" method="post">
                          <input type="hidden" name="operation" value="remove_item" />
                          <input type="hidden" name="quotation_id" value={quotation.id} />
                          <input type="hidden" name="quotation_item_id" value={item.id} />
                          <button type="submit" className="button button-secondary">Xóa</button>
                        </form>
                      ) : null}
                    </td>
                  </tr>
                );
              })}
              {items.length === 0 ? <tr><td colSpan={8} className="empty-state">Chưa có line item.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      {quotation.status === "DRAFT" ? (
        <section className="content-card">
          <h2>Thêm line &amp; áp dụng giá</h2>
          <p className="muted">
            Database chọn pricing rule/tier đang hiệu lực theo SKU/product type, base quantity, print mode và số màu; giá được snapshot vào line.
          </p>
          <form action="/api/quotations/operations" method="post" className="form-stack">
            <input type="hidden" name="operation" value="add_item" />
            <input type="hidden" name="quotation_id" value={quotation.id} />
            <label>SKU / sale unit *
              <select name="sale_source" required defaultValue="">
                <option value="" disabled>Chọn SKU / đơn vị bán</option>
                {variants.map((variant) => (
                  <optgroup key={variant.id} label={`${variant.sku_code} · ${productById.get(variant.product_id)?.name ?? ""}`}>
                    <option value={`${variant.id}|`}>
                      Base unit · {variant.base_inventory_unit}
                    </option>
                    {(packagingByVariant.get(variant.id) ?? []).map((pkg) => (
                      <option key={pkg.id} value={`${variant.id}|${pkg.id}`}>
                        {pkg.package_name} ({num(pkg.units_per_package)} {variant.base_inventory_unit})
                      </option>
                    ))}
                  </optgroup>
                ))}
              </select>
            </label>
            <div className="form-row">
              <label>Sale quantity *<input type="number" name="sale_quantity" min="0.000001" step="any" required /></label>
              <label>Discount amount<input type="number" name="discount_amount" min="0" step="any" defaultValue="0" /></label>
            </div>
            <div className="form-row">
              <label>Print mode
                <select name="print_mode" defaultValue="PLAIN">
                  <option value="PLAIN">PLAIN / no print</option>
                  <option value="PRINTED">PRINTED</option>
                </select>
              </label>
              <label>Print color count<input type="number" name="print_color_count" min="1" step="1" /></label>
            </div>
            <label>Print specification<textarea name="print_specification" rows={2} placeholder="Màu, vị trí, yêu cầu in..." /></label>
            <div className="form-row">
              <label>Artwork reference<input name="artwork_reference" placeholder="Tên file / link tham chiếu" /></label>
              <label>Requested due date<input type="date" name="requested_due_date" /></label>
            </div>
            <label>Notes<textarea name="notes" rows={2} /></label>
            <button type="submit" className="button button-primary">Thêm line theo pricing rule</button>
          </form>
        </section>
      ) : null}
    </main>
  );
}

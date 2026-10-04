import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentRoles } from "@/lib/auth/roles";
import { SupabaseRestError, supabaseRest } from "@/lib/supabase/rest";

type Customer = {
  id: string;
  display_name: string;
  customer_code: string | null;
  is_active: boolean;
};

type Quotation = {
  id: string;
  quotation_number: string;
  customer_id: string;
  status: string;
  quotation_date: string;
  valid_until: string | null;
  currency_code: string;
  created_by_user_id: string | null;
  notes: string | null;
  updated_at: string;
};

type Total = {
  quotation_id: string;
  subtotal_amount: number;
  discount_amount: number;
  total_amount: number;
  currency_code: string;
};

type PageProps = {
  searchParams: Promise<{ error?: string }>;
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
  return new Intl.DateTimeFormat("vi-VN", { dateStyle: "short" }).format(
    new Date(`${value}T00:00:00`),
  );
}

export default async function QuotationsPage({ searchParams }: PageProps) {
  const roles = await getCurrentRoles();
  const canUse = roles.has("OWNER_ADMIN") || roles.has("SALES");
  const state = await searchParams;

  if (!canUse) {
    return (
      <main className="app-shell">
        <header className="topbar">
          <div><p className="eyebrow">OPS-WEBAPP · OPS-030</p><h1>Quotations</h1></div>
          <Link href="/" className="button button-secondary">Trang chủ</Link>
        </header>
        <section className="content-card">
          <p className="permission-note">Báo giá dành cho OWNER/ADMIN và SALES.</p>
        </section>
      </main>
    );
  }

  let quotations: Quotation[];
  let customers: Customer[];
  let totals: Total[];

  try {
    [quotations, customers, totals] = await Promise.all([
      supabaseRest<Quotation[]>(
        "quotations?select=id,quotation_number,customer_id,status,quotation_date,valid_until,currency_code,created_by_user_id,notes,updated_at&order=updated_at.desc&limit=500",
      ),
      supabaseRest<Customer[]>(
        "customers?select=id,display_name,customer_code,is_active&is_active=eq.true&order=display_name.asc&limit=2000",
      ),
      supabaseRest<Total[]>(
        "quotation_totals?select=quotation_id,subtotal_amount,discount_amount,total_amount,currency_code&limit=500",
      ),
    ]);
  } catch (error) {
    if (error instanceof SupabaseRestError && error.status === 401) redirect("/login?error=session");
    throw error;
  }

  const customerById = new Map(customers.map((row) => [row.id, row]));
  const totalById = new Map(totals.map((row) => [row.quotation_id, row]));

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">OPS-WEBAPP · OPS-030</p>
          <h1>Quotations</h1>
          <p className="muted">
            Báo giá theo quantity pricing; giá bán được snapshot khi thêm line để giữ nguyên lịch sử.
          </p>
        </div>
        <div className="hero-actions">
          <Link href="/costing" className="button button-secondary">Pricing rules</Link>
          <Link href="/" className="button button-secondary">Trang chủ</Link>
        </div>
      </header>

      {state.error ? (
        <section className="content-card">
          <p className="permission-note">Không thể hoàn tất quotation action ({state.error}).</p>
        </section>
      ) : null}

      <section className="dashboard-grid">
        <article className="content-card">
          <div className="section-heading">
            <div>
              <h2>Danh sách báo giá</h2>
              <p className="muted">{quotations.length} báo giá</p>
            </div>
          </div>
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Number</th><th>Customer</th><th>Date</th><th>Valid until</th><th>Status</th><th>Total</th></tr>
              </thead>
              <tbody>
                {quotations.map((quotation) => {
                  const total = totalById.get(quotation.id);
                  return (
                    <tr key={quotation.id}>
                      <td><Link href={`/quotations/${quotation.id}`}><strong>{quotation.quotation_number}</strong></Link></td>
                      <td>{customerById.get(quotation.customer_id)?.display_name ?? "—"}</td>
                      <td>{date(quotation.quotation_date)}</td>
                      <td>{date(quotation.valid_until)}</td>
                      <td>{quotation.status}</td>
                      <td>{total ? money(total.total_amount, total.currency_code) : money(0, quotation.currency_code)}</td>
                    </tr>
                  );
                })}
                {quotations.length === 0 ? (
                  <tr><td colSpan={6} className="empty-state">Chưa có báo giá.</td></tr>
                ) : null}
              </tbody>
            </table>
          </div>
        </article>

        <aside className="content-card">
          <h2>Tạo báo giá</h2>
          <form action="/api/quotations/operations" method="post" className="form-stack">
            <input type="hidden" name="operation" value="create" />
            <label>Quotation number *<input name="quotation_number" required placeholder="QT-2026-0001" /></label>
            <label>Khách hàng *
              <select name="customer_id" required defaultValue="">
                <option value="" disabled>Chọn khách hàng</option>
                {customers.map((customer) => (
                  <option key={customer.id} value={customer.id}>
                    {customer.customer_code ? `${customer.customer_code} · ` : ""}{customer.display_name}
                  </option>
                ))}
              </select>
            </label>
            <div className="form-row">
              <label>Valid until<input type="date" name="valid_until" /></label>
              <label>Currency<input name="currency_code" defaultValue="VND" pattern="[A-Za-z]{3}" required /></label>
            </div>
            <label>Ghi chú<textarea name="notes" rows={3} /></label>
            <button type="submit" className="button button-primary">Tạo DRAFT quotation</button>
          </form>
        </aside>
      </section>
    </main>
  );
}

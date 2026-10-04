"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { getBrowserSupabase } from "@/lib/supabase/browser";

type ModuleKey =
  | "dashboard"
  | "customers"
  | "suppliers"
  | "products"
  | "purchases"
  | "receipts"
  | "quotations"
  | "sales-orders"
  | "deliveries"
  | "payments"
  | "receivables"
  | "inventory"
  | "print-jobs"
  | "production"
  | "tasks"
  | "costing";

type ModuleGroup = "Tổng quan" | "Bán hàng" | "Kho & mua hàng" | "Sản xuất" | "Tài chính";

type ModuleDefinition = {
  key: ModuleKey;
  label: string;
  description: string;
  group: ModuleGroup;
  roles: string[];
  source?: string;
  rpc?: string;
  rpcArgs?: Record<string, unknown>;
};

const MODULES: ModuleDefinition[] = [
  { key: "dashboard", label: "Tổng quan", description: "Role-aware browser session", group: "Tổng quan", roles: [] },
  { key: "customers", label: "Khách hàng", description: "Customer master", group: "Bán hàng", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING"], source: "customers" },
  { key: "quotations", label: "Báo giá", description: "Quotations", group: "Bán hàng", roles: ["OWNER_ADMIN", "SALES"], source: "quotations" },
  { key: "sales-orders", label: "Đơn bán", description: "Sales orders", group: "Bán hàng", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING"], source: "sales_orders" },
  { key: "deliveries", label: "Giao hàng", description: "Delivery operations", group: "Bán hàng", roles: ["OWNER_ADMIN", "SALES", "WAREHOUSE"], source: "deliveries" },
  { key: "suppliers", label: "Nhà cung cấp", description: "Supplier master", group: "Kho & mua hàng", roles: ["OWNER_ADMIN", "WAREHOUSE"], source: "suppliers" },
  { key: "products", label: "Sản phẩm", description: "Product / SKU master", group: "Kho & mua hàng", roles: ["OWNER_ADMIN", "SALES", "WAREHOUSE"], source: "products" },
  { key: "purchases", label: "Mua hàng", description: "Purchase orders", group: "Kho & mua hàng", roles: ["OWNER_ADMIN", "ACCOUNTING", "WAREHOUSE"], source: "purchase_orders" },
  { key: "receipts", label: "Nhập kho", description: "Goods receipts", group: "Kho & mua hàng", roles: ["OWNER_ADMIN", "WAREHOUSE"], source: "goods_receipts" },
  { key: "inventory", label: "Tồn kho", description: "Low-stock operational view", group: "Kho & mua hàng", roles: ["OWNER_ADMIN", "WAREHOUSE"], source: "inventory_low_stock" },
  { key: "print-jobs", label: "Lệnh in", description: "Owner/admin production tracking RPC", group: "Sản xuất", roles: ["OWNER_ADMIN"], rpc: "print_job_tracking", rpcArgs: { p_print_job_id: null } },
  { key: "production", label: "Sản xuất của tôi", description: "Assigned production queue RPC", group: "Sản xuất", roles: ["PRINTER_PRODUCTION"], rpc: "production_mobile_work_queue" },
  { key: "tasks", label: "Công việc", description: "Operational assignment queue", group: "Sản xuất", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING", "WAREHOUSE", "PRINTER_PRODUCTION"], source: "operational_task_queue" },
  { key: "payments", label: "Thanh toán", description: "Customer payments", group: "Tài chính", roles: ["OWNER_ADMIN", "ACCOUNTING"], source: "customer_payments" },
  { key: "receivables", label: "Công nợ", description: "Sanitized receivable follow-up", group: "Tài chính", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING"], source: "sales_receivable_followup" },
  { key: "costing", label: "Giá vốn", description: "Pricing rules", group: "Tài chính", roles: ["OWNER_ADMIN", "ACCOUNTING"], source: "pricing_rules" },
];

const GROUPS: ModuleGroup[] = ["Tổng quan", "Bán hàng", "Kho & mua hàng", "Sản xuất", "Tài chính"];

function hasAnyRole(userRoles: Set<string>, allowed: string[]) {
  return allowed.length === 0 || allowed.some((role) => userRoles.has(role));
}

function readRoute(): ModuleKey {
  if (typeof window === "undefined") return "dashboard";
  const value = window.location.hash.replace(/^#\/?/, "") as ModuleKey;
  return MODULES.some((module) => module.key === value) ? value : "dashboard";
}

function formatCell(value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Có" : "Không";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function safeColumns(rows: Record<string, unknown>[], isProduction: boolean) {
  const keys = Array.from(new Set(rows.flatMap((row) => Object.keys(row))));
  if (!isProduction) return keys.slice(0, 10);
  const forbidden = /(cost|margin|profit|receivable|debt|payment|amount|price)/i;
  return keys.filter((key) => !forbidden.test(key)).slice(0, 10);
}

async function loadRoles(client: SupabaseClient) {
  const memberships = await client.from("user_roles").select("role_id");
  if (memberships.error) throw memberships.error;

  const ids = (memberships.data ?? []).map((row) => row.role_id).filter(Boolean);
  if (ids.length === 0) return new Set<string>();

  const roles = await client.from("roles").select("id,code").in("id", ids);
  if (roles.error) throw roles.error;
  return new Set((roles.data ?? []).map((role) => role.code));
}

function Login({
  client,
  configMissing,
}: {
  client: SupabaseClient | null;
  configMissing: boolean;
}) {
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!client) return;
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    const password = String(form.get("password") ?? "");
    if (!email || !password) {
      setError("Vui lòng nhập email và mật khẩu.");
      return;
    }

    setBusy(true);
    setError("");
    const result = await client.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (result.error) setError("Email hoặc mật khẩu không hợp lệ.");
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-brand">
          <span className="brand-mark">M</span>
          <div>
            <strong>OPS WebApp</strong>
            <small>MAGASIN Operations</small>
          </div>
        </div>
        <div className="auth-heading">
          <span className="eyebrow">Hệ thống vận hành nội bộ</span>
          <h1>Đăng nhập</h1>
          <p>Phiên đăng nhập dùng Supabase Auth. Quyền dữ liệu vẫn do RLS/RPC của database quyết định.</p>
        </div>
        {configMissing ? (
          <div className="alert alert-danger">
            Chưa cấu hình NEXT_PUBLIC_SUPABASE_URL và NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY cho bản build.
          </div>
        ) : null}
        {error ? <div className="alert alert-danger">{error}</div> : null}
        <form className="form-stack" onSubmit={submit}>
          <label className="form-field">
            <span>Email</span>
            <input name="email" type="email" autoComplete="email" placeholder="name@example.com" required />
          </label>
          <label className="form-field">
            <span>Mật khẩu</span>
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <button className="btn btn-primary btn-block" disabled={!client || busy} type="submit">
            {busy ? "Đang đăng nhập..." : "Đăng nhập"}
          </button>
        </form>
      </section>
    </main>
  );
}

function PageHeader({
  definition,
  action,
}: {
  definition: ModuleDefinition;
  action?: React.ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <div className="breadcrumbs">
          <span>OPS</span>
          <span>/</span>
          <span>{definition.group}</span>
          <span>/</span>
          <strong>{definition.label}</strong>
        </div>
        <h1>{definition.label}</h1>
        <p>{definition.description}</p>
      </div>
      {action ? <div className="page-actions">{action}</div> : null}
    </header>
  );
}

function Dashboard({ roles, modules }: { roles: Set<string>; modules: ModuleDefinition[] }) {
  const definition = MODULES[0];
  const moduleCount = modules.filter((module) => module.key !== "dashboard").length;

  return (
    <>
      <PageHeader definition={definition} />
      <section className="stat-grid">
        <article className="stat-card">
          <span className="stat-label">Vai trò được cấp</span>
          <strong>{roles.size}</strong>
          <span className="stat-note">Theo Supabase role membership</span>
        </article>
        <article className="stat-card">
          <span className="stat-label">Phân hệ khả dụng</span>
          <strong>{moduleCount}</strong>
          <span className="stat-note">Hiển thị theo vai trò hiện tại</span>
        </article>
        <article className="stat-card">
          <span className="stat-label">Runtime</span>
          <strong>Static</strong>
          <span className="stat-note">GitHub Pages compatible</span>
        </article>
      </section>

      <section className="panel">
        <div className="panel-header">
          <div>
            <h2>Vai trò hiện tại</h2>
            <p>Điều hướng được lọc theo vai trò; dữ liệu vẫn được bảo vệ bằng RLS/RPC.</p>
          </div>
        </div>
        <div className="panel-body role-list">
          {Array.from(roles).map((role) => (
            <span className="status-badge status-info" key={role}>{role}</span>
          ))}
          {roles.size === 0 ? <div className="empty-inline">Chưa được gán vai trò vận hành.</div> : null}
        </div>
      </section>

      <section className="module-grid">
        {modules.filter((module) => module.key !== "dashboard").map((module) => (
          <button
            className="module-card"
            key={module.key}
            onClick={() => {
              window.location.hash = `#/${module.key}`;
            }}
          >
            <span className="module-group">{module.group}</span>
            <strong>{module.label}</strong>
            <span>{module.description}</span>
          </button>
        ))}
      </section>
    </>
  );
}

function DataModule({
  client,
  definition,
  isProduction,
}: {
  client: SupabaseClient;
  definition: ModuleDefinition;
  isProduction: boolean;
}) {
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(true);
  const [filter, setFilter] = useState("");

  useEffect(() => {
    let cancelled = false;

    async function run() {
      setBusy(true);
      setError("");
      let data: unknown = [];
      let requestError: { message: string } | null = null;

      if (definition.rpc) {
        const result = await client.rpc(definition.rpc, definition.rpcArgs ?? {});
        data = result.data;
        requestError = result.error;
      } else if (definition.source) {
        const result = await client.from(definition.source).select("*").limit(100);
        data = result.data;
        requestError = result.error;
      }

      if (cancelled) return;
      if (requestError) {
        setError(requestError.message);
        setRows([]);
      } else {
        setRows(Array.isArray(data) ? (data as Record<string, unknown>[]) : []);
      }
      setBusy(false);
    }

    void run();
    return () => {
      cancelled = true;
    };
  }, [client, definition]);

  const columns = safeColumns(rows, isProduction);
  const visibleRows = useMemo(() => {
    const normalized = filter.trim().toLowerCase();
    if (!normalized) return rows;
    return rows.filter((row) =>
      columns.some((column) => formatCell(row[column]).toLowerCase().includes(normalized)),
    );
  }, [columns, filter, rows]);

  return (
    <>
      <PageHeader
        definition={definition}
        action={
          <button className="btn btn-secondary" onClick={() => window.location.reload()}>
            Làm mới
          </button>
        }
      />

      <section className="panel">
        <div className="panel-toolbar">
          <div className="search-field">
            <span aria-hidden="true">⌕</span>
            <input
              aria-label="Lọc dữ liệu"
              value={filter}
              onChange={(event) => setFilter(event.target.value)}
              placeholder="Lọc nhanh dữ liệu đang hiển thị..."
            />
          </div>
          <span className="record-count">{visibleRows.length} / {rows.length} bản ghi</span>
        </div>

        {busy ? (
          <div className="state-block">
            <span className="spinner" aria-hidden="true" />
            <strong>Đang tải dữ liệu</strong>
            <p>Đang đọc dữ liệu được cấp quyền từ Supabase.</p>
          </div>
        ) : null}

        {error ? (
          <div className="alert alert-danger">
            <strong>Không thể tải dữ liệu.</strong>
            <span>Supabase từ chối hoặc không thể đọc dữ liệu: {error}</span>
          </div>
        ) : null}

        {!busy && !error && rows.length === 0 ? (
          <div className="state-block">
            <span className="empty-icon" aria-hidden="true">□</span>
            <strong>Chưa có dữ liệu</strong>
            <p>Không có dữ liệu khả dụng cho tài khoản hiện tại.</p>
          </div>
        ) : null}

        {!busy && !error && rows.length > 0 && visibleRows.length === 0 ? (
          <div className="state-block compact">
            <strong>Không tìm thấy kết quả phù hợp.</strong>
            <p>Hãy thử thay đổi nội dung lọc.</p>
          </div>
        ) : null}

        {visibleRows.length > 0 ? (
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>{columns.map((column) => <th key={column}>{column}</th>)}</tr>
              </thead>
              <tbody>
                {visibleRows.map((row, index) => (
                  <tr key={String(row.id ?? row.task_id ?? row.print_job_id ?? index)}>
                    {columns.map((column) => <td key={column}>{formatCell(row[column])}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </section>
    </>
  );
}

export default function HomePage() {
  const [client, setClient] = useState<SupabaseClient | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [roles, setRoles] = useState<Set<string>>(new Set());
  const [route, setRoute] = useState<ModuleKey>("dashboard");
  const [authReady, setAuthReady] = useState(false);
  const [roleError, setRoleError] = useState("");
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  useEffect(() => {
    const supabase = getBrowserSupabase();
    const onHashChange = () => setRoute(readRoute());
    window.addEventListener("hashchange", onHashChange);

    queueMicrotask(() => setRoute(readRoute()));

    if (!supabase) {
      queueMicrotask(() => setAuthReady(true));
      return () => window.removeEventListener("hashchange", onHashChange);
    }

    void supabase.auth.getSession().then(({ data }) => {
      setClient(supabase);
      setSession(data.session);
      setAuthReady(true);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setClient(supabase);
      setSession(nextSession);
      setAuthReady(true);
      if (!nextSession) {
        setRoles(new Set());
        setRoleError("");
      }
    });

    return () => {
      listener.subscription.unsubscribe();
      window.removeEventListener("hashchange", onHashChange);
    };
  }, []);

  useEffect(() => {
    if (!client || !session) return;

    let cancelled = false;
    void loadRoles(client)
      .then((nextRoles) => {
        if (!cancelled) {
          setRoles(nextRoles);
          setRoleError("");
        }
      })
      .catch((error: unknown) => {
        if (!cancelled) {
          setRoleError(error instanceof Error ? error.message : "Không thể tải vai trò.");
        }
      });

    return () => {
      cancelled = true;
    };
  }, [client, session]);

  const visibleModules = useMemo(
    () => MODULES.filter((module) => hasAnyRole(roles, module.roles)),
    [roles],
  );

  const activeDefinition =
    visibleModules.find((module) => module.key === route) ??
    visibleModules.find((module) => module.key === "dashboard") ??
    MODULES[0];

  if (!authReady) {
    return (
      <main className="auth-page">
        <section className="auth-card state-block">
          <span className="spinner" aria-hidden="true" />
          <strong>Đang khởi tạo phiên đăng nhập</strong>
        </section>
      </main>
    );
  }

  if (!session) {
    return <Login client={client} configMissing={authReady && !client} />;
  }

  const isProduction = roles.has("PRINTER_PRODUCTION") && !roles.has("OWNER_ADMIN");

  return (
    <div className="app-shell">
      <aside className={mobileNavOpen ? "sidebar sidebar-open" : "sidebar"}>
        <div className="sidebar-head">
          <div className="brand-lockup">
            <span className="brand-mark">M</span>
            <div>
              <strong>OPS WebApp</strong>
              <small>Operations</small>
            </div>
          </div>
          <button
            className="icon-btn sidebar-close"
            aria-label="Đóng menu"
            onClick={() => setMobileNavOpen(false)}
          >
            ×
          </button>
        </div>

        <nav className="sidebar-nav" aria-label="Điều hướng phân hệ">
          {GROUPS.map((group) => {
            const grouped = visibleModules.filter((module) => module.group === group);
            if (grouped.length === 0) return null;
            return (
              <div className="nav-group" key={group}>
                <div className="nav-group-label">{group}</div>
                {grouped.map((module) => (
                  <button
                    className={activeDefinition.key === module.key ? "nav-link active" : "nav-link"}
                    key={module.key}
                    onClick={() => {
                      window.location.hash = `#/${module.key}`;
                      setMobileNavOpen(false);
                    }}
                  >
                    <span className="nav-dot" aria-hidden="true" />
                    <span>{module.label}</span>
                  </button>
                ))}
              </div>
            );
          })}
        </nav>

        <div className="sidebar-account">
          <span className="account-avatar">{(session.user.email ?? "U").slice(0, 1).toUpperCase()}</span>
          <div>
            <strong>{session.user.email ?? "Tài khoản vận hành"}</strong>
            <small>{Array.from(roles).slice(0, 2).join(" · ") || "Chưa có vai trò"}</small>
          </div>
        </div>
      </aside>

      {mobileNavOpen ? (
        <button className="sidebar-backdrop" aria-label="Đóng menu" onClick={() => setMobileNavOpen(false)} />
      ) : null}

      <div className="app-main">
        <header className="app-topbar">
          <button
            className="icon-btn menu-toggle"
            aria-label="Mở menu"
            onClick={() => setMobileNavOpen(true)}
          >
            ☰
          </button>
          <div className="runtime-badges">
            <span className="status-badge">STATIC PAGES</span>
            <span className="status-badge status-success">SUPABASE AUTH</span>
          </div>
          <button
            className="btn btn-ghost-danger"
            onClick={() => {
              void client?.auth.signOut();
            }}
          >
            Đăng xuất
          </button>
        </header>

        <main className="page-body">
          {roleError ? <div className="alert alert-danger">{roleError}</div> : null}

          {activeDefinition.key === "dashboard" ? (
            <Dashboard roles={roles} modules={visibleModules} />
          ) : client ? (
            <DataModule
              client={client}
              definition={activeDefinition}
              isProduction={isProduction}
            />
          ) : null}
        </main>
      </div>
    </div>
  );
}

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

type ModuleDefinition = {
  key: ModuleKey;
  label: string;
  description: string;
  roles: string[];
  source?: string;
  rpc?: string;
  rpcArgs?: Record<string, unknown>;
};

const MODULES: ModuleDefinition[] = [
  { key: "dashboard", label: "Tổng quan", description: "Role-aware browser session", roles: [] },
  { key: "customers", label: "Khách hàng", description: "Customer master", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING"], source: "customers" },
  { key: "suppliers", label: "Nhà cung cấp", description: "Supplier master", roles: ["OWNER_ADMIN", "WAREHOUSE"], source: "suppliers" },
  { key: "products", label: "Sản phẩm", description: "Product / SKU master", roles: ["OWNER_ADMIN", "SALES", "WAREHOUSE"], source: "products" },
  { key: "purchases", label: "Mua hàng", description: "Purchase orders", roles: ["OWNER_ADMIN", "ACCOUNTING", "WAREHOUSE"], source: "purchase_orders" },
  { key: "receipts", label: "Nhập kho", description: "Goods receipts", roles: ["OWNER_ADMIN", "WAREHOUSE"], source: "goods_receipts" },
  { key: "quotations", label: "Báo giá", description: "Quotations", roles: ["OWNER_ADMIN", "SALES"], source: "quotations" },
  { key: "sales-orders", label: "Đơn bán", description: "Sales orders", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING"], source: "sales_orders" },
  { key: "deliveries", label: "Giao hàng", description: "Delivery operations", roles: ["OWNER_ADMIN", "SALES", "WAREHOUSE"], source: "deliveries" },
  { key: "payments", label: "Thanh toán", description: "Customer payments", roles: ["OWNER_ADMIN", "ACCOUNTING"], source: "customer_payments" },
  { key: "receivables", label: "Công nợ", description: "Sanitized receivable follow-up", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING"], source: "sales_receivable_followup" },
  { key: "inventory", label: "Tồn kho", description: "Low-stock operational view", roles: ["OWNER_ADMIN", "WAREHOUSE"], source: "inventory_low_stock" },
  { key: "print-jobs", label: "Lệnh in", description: "Owner/admin production tracking RPC", roles: ["OWNER_ADMIN"], rpc: "print_job_tracking", rpcArgs: { p_print_job_id: null } },
  { key: "production", label: "Sản xuất của tôi", description: "Assigned production queue RPC", roles: ["PRINTER_PRODUCTION"], rpc: "production_mobile_work_queue" },
  { key: "tasks", label: "Công việc", description: "Operational assignment queue", roles: ["OWNER_ADMIN", "SALES", "ACCOUNTING", "WAREHOUSE", "PRINTER_PRODUCTION"], source: "operational_task_queue" },
  { key: "costing", label: "Giá vốn", description: "Pricing rules", roles: ["OWNER_ADMIN", "ACCOUNTING"], source: "pricing_rules" },
];

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
    if (result.error) {
      setError("Email hoặc mật khẩu không hợp lệ.");
    }
  }

  return (
    <main className="auth">
      <section className="card">
        <div className="brand">
          OPS WebApp
          <small>GitHub Pages + Supabase browser session</small>
        </div>
        <h1>Đăng nhập vận hành</h1>
        <p className="muted">
          Session được Supabase Auth lưu trong trình duyệt. Quyền dữ liệu vẫn do RLS/RPC của database quyết định.
        </p>
        {configMissing ? (
          <div className="alert error">
            Chưa cấu hình NEXT_PUBLIC_SUPABASE_URL và NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY cho bản build.
          </div>
        ) : null}
        {error ? <div className="alert error">{error}</div> : null}
        <form className="form" onSubmit={submit}>
          <label>
            Email
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            Mật khẩu
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <button className="button primary" disabled={!client || busy} type="submit">
            {busy ? "Đang đăng nhập..." : "Đăng nhập"}
          </button>
        </form>
      </section>
    </main>
  );
}

function Dashboard({ roles, modules }: { roles: Set<string>; modules: ModuleDefinition[] }) {
  return (
    <>
      <div className="topbar">
        <div>
          <h1 className="module-title">Operations Dashboard</h1>
          <p className="muted">Static browser runtime · Supabase RLS/RPC authorization boundary</p>
        </div>
      </div>
      <section className="card">
        <h2>Vai trò hiện tại</h2>
        <div>
          {Array.from(roles).map((role) => (
            <span className="badge" key={role}>{role}</span>
          ))}
          {roles.size === 0 ? <span className="muted">Chưa được gán vai trò vận hành.</span> : null}
        </div>
      </section>
      <div style={{ height: 14 }} />
      <section className="grid">
        {modules.filter((module) => module.key !== "dashboard").map((module) => (
          <article className="card" key={module.key}>
            <div className="muted">{module.description}</div>
            <div className="kpi">{module.label}</div>
          </article>
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

  return (
    <>
      <div className="topbar">
        <div>
          <h1 className="module-title">{definition.label}</h1>
          <p className="muted">{definition.description}</p>
        </div>
        <button className="button" onClick={() => window.location.reload()}>Làm mới</button>
      </div>

      <section className="card">
        {busy ? <p className="muted">Đang tải dữ liệu...</p> : null}
        {error ? (
          <div className="alert error">
            Supabase từ chối hoặc không thể đọc dữ liệu: {error}
          </div>
        ) : null}
        {!busy && !error && rows.length === 0 ? (
          <p className="muted">Không có dữ liệu khả dụng cho tài khoản hiện tại.</p>
        ) : null}
        {rows.length > 0 ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>{columns.map((column) => <th key={column}>{column}</th>)}</tr>
              </thead>
              <tbody>
                {rows.map((row, index) => (
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
  const [configMissing, setConfigMissing] = useState(false);

  useEffect(() => {
    const supabase = getBrowserSupabase();
    setClient(supabase);
    setConfigMissing(!supabase);
    setRoute(readRoute());

    const onHashChange = () => setRoute(readRoute());
    window.addEventListener("hashchange", onHashChange);

    if (!supabase) {
      setAuthReady(true);
      return () => window.removeEventListener("hashchange", onHashChange);
    }

    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setAuthReady(true);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setAuthReady(true);
    });

    return () => {
      listener.subscription.unsubscribe();
      window.removeEventListener("hashchange", onHashChange);
    };
  }, []);

  useEffect(() => {
    if (!client || !session) {
      setRoles(new Set());
      return;
    }

    let cancelled = false;
    setRoleError("");
    void loadRoles(client)
      .then((nextRoles) => {
        if (!cancelled) setRoles(nextRoles);
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
    return <main className="auth"><section className="card">Đang khởi tạo session...</section></main>;
  }

  if (!session) {
    return <Login client={client} configMissing={configMissing} />;
  }

  const isProduction = roles.has("PRINTER_PRODUCTION") && !roles.has("OWNER_ADMIN");

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          OPS WebApp
          <small>{session.user.email ?? session.user.id}</small>
        </div>
        <nav className="nav">
          {visibleModules.map((module) => (
            <button
              className={activeDefinition.key === module.key ? "active" : ""}
              key={module.key}
              onClick={() => {
                window.location.hash = `#/${module.key}`;
              }}
            >
              {module.label}
            </button>
          ))}
        </nav>
      </aside>
      <main className="main">
        <div className="topbar">
          <div>
            <span className="badge">STATIC PAGES</span>
            <span className="badge">SUPABASE AUTH</span>
          </div>
          <button
            className="button danger"
            onClick={() => {
              void client?.auth.signOut();
            }}
          >
            Đăng xuất
          </button>
        </div>

        {roleError ? <div className="alert error">{roleError}</div> : null}

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
  );
}

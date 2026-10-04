import Link from "next/link";
import { redirect } from "next/navigation";
import { getAccessToken } from "@/lib/supabase/rest";

type LoginPageProps = {
  searchParams: Promise<{ error?: string }>;
};

const errorMessages: Record<string, string> = {
  missing: "Vui lòng nhập email và mật khẩu.",
  invalid: "Email hoặc mật khẩu không hợp lệ.",
  session: "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.",
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const accessToken = await getAccessToken();
  if (accessToken) {
    redirect("/customers");
  }

  const { error } = await searchParams;

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <p className="eyebrow">OPS-WEBAPP</p>
        <h1>Đăng nhập vận hành</h1>
        <p className="muted">
          Dùng tài khoản Supabase Auth của hệ thống OPS độc lập.
        </p>

        {error ? (
          <div className="alert alert-error">
            {errorMessages[error] ?? "Không thể đăng nhập."}
          </div>
        ) : null}

        <form action="/api/auth/login" method="post" className="form-stack">
          <label>
            Email
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            Mật khẩu
            <input
              name="password"
              type="password"
              autoComplete="current-password"
              required
            />
          </label>
          <button type="submit" className="button button-primary">
            Đăng nhập
          </button>
        </form>

        <Link href="/" className="text-link">
          Về trang đầu
        </Link>
      </section>
    </main>
  );
}

import Link from "next/link";

export default function HomePage() {
  return (
    <main className="shell">
      <section className="panel">
        <p className="eyebrow">OPS-WEBAPP</p>
        <h1>Operations WebApp</h1>
        <p>
          Hệ thống vận hành độc lập cho khách hàng, bán hàng, sản xuất, kho và
          tài chính.
        </p>
        <div className="hero-actions">
          <Link href="/customers" className="button button-primary">
            Mở module Khách hàng
          </Link>
          <Link href="/login" className="button button-secondary">
            Đăng nhập
          </Link>
        </div>
      </section>
    </main>
  );
}

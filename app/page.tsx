import Link from "next/link";

export default function HomePage() {
  return (
    <main className="shell">
      <section className="panel">
        <p className="eyebrow">OPS-WEBAPP</p>
        <h1>Operations WebApp</h1>
        <p>
          Hệ thống vận hành độc lập cho khách hàng, nhà cung cấp, sản phẩm, giá
          vốn, bán hàng, sản xuất, kho và tài chính.
        </p>
        <div className="hero-actions">
          <Link href="/customers" className="button button-primary">Khách hàng</Link>
          <Link href="/suppliers" className="button button-secondary">Nhà cung cấp</Link>
          <Link href="/products" className="button button-secondary">Sản phẩm &amp; SKU</Link>
          <Link href="/costing" className="button button-secondary">Giá vốn &amp; Pricing</Link>
          <Link href="/login" className="button button-secondary">Đăng nhập</Link>
        </div>
      </section>
    </main>
  );
}

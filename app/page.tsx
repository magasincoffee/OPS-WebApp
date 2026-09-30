import Link from "next/link";

export default function HomePage() {
  return (
    <main className="shell">
      <section className="panel">
        <p className="eyebrow">OPS-WEBAPP</p>
        <h1>Operations WebApp</h1>
        <p>
          Hệ thống vận hành độc lập cho khách hàng, nhà cung cấp, sản phẩm, giá
          vốn, mua hàng, nhận hàng, kho, bán hàng, sản xuất và tài chính.
        </p>
        <div className="hero-actions">
          <Link href="/customers" className="button button-primary">Khách hàng</Link>
          <Link href="/suppliers" className="button button-secondary">Nhà cung cấp</Link>
          <Link href="/products" className="button button-secondary">Sản phẩm &amp; SKU</Link>
          <Link href="/costing" className="button button-secondary">Giá vốn &amp; Pricing</Link>
          <Link href="/purchases" className="button button-secondary">Purchase Orders</Link>
          <Link href="/receipts" className="button button-secondary">Goods Receipts</Link>
          <Link href="/inventory" className="button button-secondary">Inventory</Link>
          <Link href="/quotations" className="button button-secondary">Quotations</Link>
          <Link href="/sales-orders" className="button button-secondary">Sales Orders</Link>
          <Link href="/deliveries" className="button button-secondary">Deliveries</Link>
          <Link href="/print-jobs" className="button button-secondary">Print Jobs</Link>
          <Link href="/production" className="button button-secondary">Production Queue</Link>
          <Link href="/payments" className="button button-secondary">Customer Payments</Link>
          <Link href="/login" className="button button-secondary">Đăng nhập</Link>
        </div>
      </section>
    </main>
  );
}

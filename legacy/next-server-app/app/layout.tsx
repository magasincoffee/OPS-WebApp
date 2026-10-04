import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "OPS WebApp",
  description: "Standalone operations web application",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="vi">
      <body>{children}</body>
    </html>
  );
}

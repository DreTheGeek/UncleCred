import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Uncle Cred Studio",
  description: "The studio that writes, shoots, and ships the show.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#0a0d12",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-mode="night">
      <body className="min-h-screen bg-bg text-txt antialiased">{children}</body>
    </html>
  );
}

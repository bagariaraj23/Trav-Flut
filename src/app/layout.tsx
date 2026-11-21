import "./globals.css";
import { Playfair_Display } from "next/font/google";

const playfair = Playfair_Display({
  subsets: ["latin"],
  weight: ["500", "600"],
  variable: "--font-display",
  display: "swap",
});

export const metadata = {
  title: "TripThread",
  description:
    "Capture journeys. Share stories. A travel-focused social platform for documenting and sharing your adventures.",
  icons: {
    icon: "/tripthread-icon.svg",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={playfair.variable}>
      <body className="bg-gray-100 font-body text-ink">{children}</body>
    </html>
  );
}

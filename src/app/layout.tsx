import "./globals.css";

export const metadata = {
  title: 'TripThread',
  description: 'Capture journeys. Share stories. A travel-focused social platform for documenting and sharing your adventures.',
  icons: {
    icon: '/tripthread-icon.svg',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="bg-gray-100">{children}</body>
    </html>
  )
}

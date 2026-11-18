export const dynamic = "force-dynamic";

import { Suspense } from "react";
import HomePageContent from "./HomePageContent";

export default function HomePage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-cream" />}>
      <HomePageContent />
    </Suspense>
  );
}

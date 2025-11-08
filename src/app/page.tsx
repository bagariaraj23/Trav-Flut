"use client";
export const dynamic = "force-dynamic";

import { Suspense } from "react";
import HomePageContent from "./HomePageContent";

export default function HomePage() {
  return (
    <Suspense fallback={<div className="text-center p-10 text-gray-500">Loading...</div>}>
      <HomePageContent />
    </Suspense>
  );
}

"use client";
export const dynamic = "force-dynamic";

import { Suspense } from "react";
import ResetSuccessContent from "./ResetSuccessContent";

export default function ResetSuccessPage() {
  return (
    <Suspense fallback={<div className="text-center p-10 text-gray-500">Loading...</div>}>
      <ResetSuccessContent />
    </Suspense>
  );
}

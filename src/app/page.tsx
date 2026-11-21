export const dynamic = "force-dynamic";

import { Suspense } from "react";
import HomePageContent from "./HomePageContent";
import { prisma } from "@/lib/prisma";

async function signedUpAccounts(): Promise<number | null> {
  try {
    return await prisma.user.count({ where: { deletedAt: null } });
  } catch {
    return null;
  }
}

export default async function HomePage() {
  const signedUp = await signedUpAccounts();
  return (
    <Suspense fallback={<div className="min-h-screen bg-cream" />}>
      <HomePageContent signedUp={signedUp} />
    </Suspense>
  );
}

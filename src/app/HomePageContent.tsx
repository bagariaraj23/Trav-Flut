"use client";

import { useSearchParams } from "next/navigation";
import LandingPage from "./landing/LandingPage";

export default function HomePageContent({ signedUp }: { signedUp: number | null }) {
  const searchParams = useSearchParams();

  return (
    <LandingPage
      error={searchParams.get("error")}
      message={searchParams.get("message")}
      signedUp={signedUp}
    />
  );
}

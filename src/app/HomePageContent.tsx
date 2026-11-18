"use client";

import { useSearchParams } from "next/navigation";
import LandingPage from "./landing/LandingPage";

export default function HomePageContent() {
  const searchParams = useSearchParams();

  return (
    <LandingPage
      error={searchParams.get("error")}
      message={searchParams.get("message")}
    />
  );
}

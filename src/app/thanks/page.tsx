import { prisma } from "@/lib/prisma";
import { publicSupporterNames } from "@/lib/chipIn";
import ThanksExperience from "./ThanksExperience";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Thank you · TripThread",
  description: "Thank you for supporting TripThread.",
};

export default async function ThanksPage({
  searchParams,
}: {
  searchParams: Promise<{ problem?: string }>;
}) {
  const params = await searchParams;
  const rows = await prisma.chipIn.findMany({
    where: { status: "PAID", displayName: { not: null } },
    orderBy: { paidAt: "desc" },
    take: 60,
    select: { displayName: true },
  });
  const names = publicSupporterNames(rows.map((row) => row.displayName));
  return <ThanksExperience names={names} problem={params.problem === "1"} />;
}

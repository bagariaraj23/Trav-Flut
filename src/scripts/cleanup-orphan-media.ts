/**
 * Opt-in cleanup for Media rows nothing references.
 *
 * A row is orphaned when it is older than --hours (default 24), has no chat
 * message, is not a trip cover, and is not attached to a thread entry.
 *
 * Dry-run unless --apply is passed. This script is never run on deploy.
 *
 *   npx tsx src/scripts/cleanup-orphan-media.ts
 *   npx tsx src/scripts/cleanup-orphan-media.ts --hours 48 --apply
 */
import { prisma } from "@/lib/prisma";
import { CloudinaryService } from "@/lib/cloudinary";

function argValue(flag: string): string | undefined {
  const index = process.argv.indexOf(flag);
  if (index === -1 || index + 1 >= process.argv.length) return undefined;
  return process.argv[index + 1];
}

async function main() {
  const hours = Number(argValue("--hours") ?? "24");
  const apply = process.argv.includes("--apply");
  if (!Number.isFinite(hours) || hours < 1) {
    console.error("[orphan-media] --hours must be a number >= 1");
    process.exitCode = 1;
    return;
  }

  const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000);
  const orphans = await prisma.media.findMany({
    where: {
      createdAt: { lt: cutoff },
      chatMessageId: null,
      threadEntries: { none: {} },
      tripCover: { none: {} },
    },
    select: {
      id: true,
      publicId: true,
      createdAt: true,
      uploadedById: true,
    },
    orderBy: { createdAt: "asc" },
    take: 500,
  });

  console.log(
    `[orphan-media] ${orphans.length} unreferenced media older than ${hours}h (cap 500)`
  );
  for (const row of orphans) {
    console.log(
      `${row.id}\t${row.publicId}\t${row.uploadedById}\t${row.createdAt.toISOString()}`
    );
  }

  if (!apply) {
    console.log(
      "[orphan-media] Dry run. Re-run with --apply to delete these rows and their Cloudinary assets."
    );
    return;
  }

  for (const row of orphans) {
    await CloudinaryService.deleteMedia(row.publicId);
    console.log(`[orphan-media] deleted ${row.publicId}`);
  }
}

main()
  .catch((error) => {
    console.error("[orphan-media] failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

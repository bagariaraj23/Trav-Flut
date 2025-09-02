import { prisma } from "@/lib/prisma";

const RESET_RETENTION_DAYS = Number(process.env.RESET_RETENTION_DAYS || 7);

export async function cleanupExpiredResets() {
  const cutoff = new Date(Date.now() - RESET_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  
  try {
    const result = await prisma.passwordReset.deleteMany({
      where: {
        OR: [
          { usedAt: { not: null } },
          { expiresAt: { lt: new Date() } }
        ],
        createdAt: { lt: cutoff }
      }
    });

    console.log(`[Cleanup] Deleted ${result.count} expired/used password reset records`);
    return result.count;
  } catch (error) {
    console.error('[Cleanup] Error cleaning up expired password resets:', error);
    throw error;
  }
}

// Run cleanup if this script is executed directly
if (require.main === module) {
  cleanupExpiredResets()
    .then((count) => {
      console.log(`Cleanup completed. Deleted ${count} records.`);
      process.exit(0);
    })
    .catch((error) => {
      console.error('Cleanup failed:', error);
      process.exit(1);
    });
}
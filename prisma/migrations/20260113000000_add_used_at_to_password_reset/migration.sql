-- AlterTable
ALTER TABLE "password_resets"
ADD COLUMN "usedAt" TIMESTAMP(3);
-- Add index for cleanup queries
CREATE INDEX "password_resets_usedAt_createdAt_idx" ON "password_resets"("usedAt", "createdAt");
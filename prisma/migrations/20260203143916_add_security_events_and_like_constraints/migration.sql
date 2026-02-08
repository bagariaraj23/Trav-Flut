/*
  Warnings:

  - You are about to drop the column `meta` on the `security_events` table. All the data in the column will be lost.
  - You are about to drop the column `type` on the `security_events` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[userId,entityType,entityId]` on the table `Like` will be added. If there are existing duplicate values, this will fail.
  - Added the required column `eventType` to the `security_events` table without a default value. This is not possible if the table is not empty.
  - Added the required column `metadata` to the `security_events` table without a default value. This is not possible if the table is not empty.

*/
-- CreateEnum
CREATE TYPE "SecurityEventType" AS ENUM ('COMMENT_REPORT', 'PROFANITY_DETECTED', 'RATE_LIMIT_HIT', 'ABUSE_DETECTED', 'UNAUTHORIZED_ACCESS');

-- DropIndex
DROP INDEX "password_resets_usedAt_createdAt_idx";

-- AlterTable
ALTER TABLE "security_events" DROP COLUMN "meta",
DROP COLUMN "type",
ADD COLUMN     "entityId" TEXT,
ADD COLUMN     "entityType" "EntityType",
ADD COLUMN     "eventType" "SecurityEventType" NOT NULL,
ADD COLUMN     "ipAddress" TEXT,
ADD COLUMN     "metadata" JSONB NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "Like_userId_entityType_entityId_key" ON "Like"("userId", "entityType", "entityId");

-- CreateIndex
CREATE INDEX "security_events_eventType_createdAt_idx" ON "security_events"("eventType", "createdAt");

-- CreateIndex
CREATE INDEX "security_events_entityType_entityId_idx" ON "security_events"("entityType", "entityId");

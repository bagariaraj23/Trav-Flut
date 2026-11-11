-- CreateEnum
CREATE TYPE "UserSafetyAction" AS ENUM ('RESTRICT', 'BLOCK');

-- AlterTable
ALTER TABLE "conversations" ADD COLUMN "createdById" TEXT;

-- CreateTable
CREATE TABLE "user_safety_relations" (
    "id" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "action" "UserSafetyAction" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_safety_relations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_safety_relations_actorId_targetId_key" ON "user_safety_relations"("actorId", "targetId");

-- CreateIndex
CREATE INDEX "user_safety_relations_actorId_action_createdAt_id_idx" ON "user_safety_relations"("actorId", "action", "createdAt" DESC, "id" DESC);

-- CreateIndex
CREATE INDEX "user_safety_relations_targetId_action_idx" ON "user_safety_relations"("targetId", "action");

-- AddForeignKey
ALTER TABLE "user_safety_relations" ADD CONSTRAINT "user_safety_relations_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_safety_relations" ADD CONSTRAINT "user_safety_relations_targetId_fkey" FOREIGN KEY ("targetId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- The group creator is the earliest admin. Later admins are not the creator.
UPDATE "conversations" AS c
SET "createdById" = sub."userId"
FROM (
  SELECT DISTINCT ON ("conversationId") "conversationId", "userId"
  FROM "conversation_participants"
  WHERE "role" = 'ADMIN'
  ORDER BY "conversationId", "joinedAt" ASC, "id" ASC
) AS sub
WHERE c."id" = sub."conversationId"
  AND c."type" = 'GROUP'
  AND c."createdById" IS NULL;

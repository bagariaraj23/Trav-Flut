/*
  Warnings:

  - You are about to drop the column `usedAt` on the `password_resets` table. All the data in the column will be lost.

*/
-- DropIndex
DROP INDEX "Like_userId_entityType_entityId_key";

-- AlterTable
ALTER TABLE "password_resets" DROP COLUMN "usedAt";

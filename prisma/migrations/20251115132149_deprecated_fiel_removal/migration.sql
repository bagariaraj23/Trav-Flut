/*
  Warnings:

  - You are about to drop the column `mediaUrl` on the `trip_thread_entries` table. All the data in the column will be lost.
  - You are about to drop the column `coverMediaUrl` on the `trips` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "trip_thread_entries" DROP COLUMN "mediaUrl";

-- AlterTable
ALTER TABLE "trips" DROP COLUMN "coverMediaUrl";

/*
  Warnings:

  - A unique constraint covering the columns `[publicId]` on the table `media` will be added. If there are existing duplicate values, this will fail.
  - Added the required column `publicId` to the `media` table without a default value. This is not possible if the table is not empty.

*/
-- CreateEnum
CREATE TYPE "MediaProcessingStatus" AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED');

-- AlterTable
ALTER TABLE "media" ADD COLUMN     "duration" DOUBLE PRECISION,
ADD COLUMN     "height" INTEGER,
ADD COLUMN     "processingStatus" "MediaProcessingStatus" NOT NULL DEFAULT 'COMPLETED',
ADD COLUMN     "publicId" TEXT NOT NULL,
ADD COLUMN     "width" INTEGER;

-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "coverMediaId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "media_publicId_key" ON "media"("publicId");

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_coverMediaId_fkey" FOREIGN KEY ("coverMediaId") REFERENCES "media"("id") ON DELETE SET NULL ON UPDATE CASCADE;

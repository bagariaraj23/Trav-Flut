-- CreateEnum
CREATE TYPE "GenerationStatus" AS ENUM ('DRAFT', 'GENERATING', 'READY', 'PUBLISHED', 'FAILED');

-- AlterTable
ALTER TABLE "trip_final_posts" ADD COLUMN     "coverMediaUrl" TEXT,
ADD COLUMN     "generationStatus" "GenerationStatus" NOT NULL DEFAULT 'DRAFT',
ADD COLUMN     "publishedAt" TIMESTAMP(3),
ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "trips" ALTER COLUMN "updatedAt" SET DEFAULT CURRENT_TIMESTAMP;

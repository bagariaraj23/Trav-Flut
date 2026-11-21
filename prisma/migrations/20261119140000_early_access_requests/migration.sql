-- CreateEnum
CREATE TYPE "EarlyAccessPlatform" AS ENUM ('ANDROID', 'IOS');

-- CreateTable
CREATE TABLE "early_access_requests" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT,
    "platform" "EarlyAccessPlatform" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdIp" TEXT,

    CONSTRAINT "early_access_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "early_access_requests_email_key" ON "early_access_requests"("email");

-- CreateIndex
CREATE INDEX "early_access_requests_platform_createdAt_idx" ON "early_access_requests"("platform", "createdAt");

-- CreateEnum
CREATE TYPE "ChipInStatus" AS ENUM ('CREATED', 'PAID', 'FAILED');

-- CreateTable
CREATE TABLE "chip_ins" (
    "id" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "status" "ChipInStatus" NOT NULL DEFAULT 'CREATED',
    "providerOrderId" TEXT,
    "providerPaymentId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "paidAt" TIMESTAMP(3),

    CONSTRAINT "chip_ins_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "chip_ins_providerOrderId_key" ON "chip_ins"("providerOrderId");

-- CreateIndex
CREATE UNIQUE INDEX "chip_ins_providerPaymentId_key" ON "chip_ins"("providerPaymentId");

-- CreateIndex
CREATE INDEX "chip_ins_status_createdAt_idx" ON "chip_ins"("status", "createdAt");

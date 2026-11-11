-- CreateEnum
CREATE TYPE "ExpenseCategory" AS ENUM ('FOOD', 'STAY', 'TRANSPORT', 'ACTIVITIES', 'SHOPPING', 'OTHER');

-- CreateEnum
CREATE TYPE "ExpenseSplitMethod" AS ENUM ('EQUAL', 'EXACT', 'PERCENT', 'SHARES');

-- CreateEnum
CREATE TYPE "TripSettlementStatus" AS ENUM ('PAID', 'PENDING', 'COMPLETED', 'FAILED', 'CANCELLED', 'DISPUTED');

-- AlterTable
ALTER TABLE "trips" ADD COLUMN "expenseCurrency" TEXT NOT NULL DEFAULT 'INR';
ALTER TABLE "trips" ADD COLUMN "totalSpendMinor" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "trips" ADD COLUMN "spendVisibleOnDiscover" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "trip_expenses" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "payerId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "category" "ExpenseCategory" NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL,
    "splitMethod" "ExpenseSplitMethod" NOT NULL,
    "note" TEXT,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "trip_expenses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_expense_shares" (
    "id" TEXT NOT NULL,
    "expenseId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "shareMinor" INTEGER NOT NULL,
    "weight" INTEGER,

    CONSTRAINT "trip_expense_shares_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trip_settlements" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "fromUserId" TEXT NOT NULL,
    "toUserId" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL,
    "status" "TripSettlementStatus" NOT NULL DEFAULT 'PAID',
    "recordedById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_settlements_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "trip_expenses_tripId_createdAt_idx" ON "trip_expenses"("tripId", "createdAt");

-- CreateIndex
CREATE INDEX "trip_expenses_tripId_deletedAt_idx" ON "trip_expenses"("tripId", "deletedAt");

-- CreateIndex
CREATE INDEX "trip_expenses_payerId_idx" ON "trip_expenses"("payerId");

-- CreateIndex
CREATE UNIQUE INDEX "trip_expense_shares_expenseId_userId_key" ON "trip_expense_shares"("expenseId", "userId");

-- CreateIndex
CREATE INDEX "trip_expense_shares_userId_idx" ON "trip_expense_shares"("userId");

-- CreateIndex
CREATE INDEX "trip_settlements_tripId_createdAt_idx" ON "trip_settlements"("tripId", "createdAt");

-- CreateIndex
CREATE INDEX "trip_settlements_fromUserId_idx" ON "trip_settlements"("fromUserId");

-- CreateIndex
CREATE INDEX "trip_settlements_toUserId_idx" ON "trip_settlements"("toUserId");

-- AddForeignKey
ALTER TABLE "trip_expenses" ADD CONSTRAINT "trip_expenses_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_expenses" ADD CONSTRAINT "trip_expenses_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_expenses" ADD CONSTRAINT "trip_expenses_payerId_fkey" FOREIGN KEY ("payerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_expense_shares" ADD CONSTRAINT "trip_expense_shares_expenseId_fkey" FOREIGN KEY ("expenseId") REFERENCES "trip_expenses"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_expense_shares" ADD CONSTRAINT "trip_expense_shares_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_settlements" ADD CONSTRAINT "trip_settlements_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_settlements" ADD CONSTRAINT "trip_settlements_fromUserId_fkey" FOREIGN KEY ("fromUserId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_settlements" ADD CONSTRAINT "trip_settlements_toUserId_fkey" FOREIGN KEY ("toUserId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_settlements" ADD CONSTRAINT "trip_settlements_recordedById_fkey" FOREIGN KEY ("recordedById") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

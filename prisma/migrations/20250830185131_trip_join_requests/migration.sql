-- CreateEnum
CREATE TYPE "TripJoinRequestStatus" AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');
-- CreateTable
CREATE TABLE "trip_join_requests" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "senderId" TEXT NOT NULL,
    "receiverId" TEXT NOT NULL,
    "status" "TripJoinRequestStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "trip_join_requests_pkey" PRIMARY KEY ("id")
);
-- CreateIndex
CREATE UNIQUE INDEX "trip_join_requests_tripId_receiverId_key" ON "trip_join_requests"("tripId", "receiverId");
-- AddForeignKey
ALTER TABLE "trip_join_requests"
ADD CONSTRAINT "trip_join_requests_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;
-- AddForeignKey
ALTER TABLE "trip_join_requests"
ADD CONSTRAINT "trip_join_requests_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
-- AddForeignKey
ALTER TABLE "trip_join_requests"
ADD CONSTRAINT "trip_join_requests_receiverId_fkey" FOREIGN KEY ("receiverId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
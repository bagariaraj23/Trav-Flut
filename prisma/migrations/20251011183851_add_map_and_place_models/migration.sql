/*
  Warnings:

  - Made the column `startDate` on table `trips` required. This step will fail if there are existing NULL values in that column.
  - Made the column `endDate` on table `trips` required. This step will fail if there are existing NULL values in that column.

*/
-- CreateEnum
CREATE TYPE "TripJoinRequestStatus" AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');

-- CreateEnum
CREATE TYPE "PlaceType" AS ENUM ('POI', 'STAY', 'FOOD', 'TRANSPORT', 'VIEWPOINT', 'OTHER');

-- CreateEnum
CREATE TYPE "PlaceSource" AS ENUM ('USER', 'GOOGLE', 'MAPBOX', 'APPLE');

-- AlterTable
ALTER TABLE "trip_thread_entries" ADD COLUMN     "placeId" TEXT;

-- AlterTable
ALTER TABLE "trips" ADD COLUMN     "boundNeLat" DOUBLE PRECISION,
ADD COLUMN     "boundNeLng" DOUBLE PRECISION,
ADD COLUMN     "boundSwLat" DOUBLE PRECISION,
ADD COLUMN     "boundSwLng" DOUBLE PRECISION,
ADD COLUMN     "centerLat" DOUBLE PRECISION,
ADD COLUMN     "centerLng" DOUBLE PRECISION,
ADD COLUMN     "endLocationId" TEXT,
ADD COLUMN     "startLocationId" TEXT,
ALTER COLUMN "startDate" SET NOT NULL,
ALTER COLUMN "endDate" SET NOT NULL;

-- CreateTable
CREATE TABLE "places" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "address" TEXT,
    "lat" DOUBLE PRECISION NOT NULL,
    "lng" DOUBLE PRECISION NOT NULL,
    "placeType" "PlaceType" NOT NULL DEFAULT 'POI',
    "source" "PlaceSource" NOT NULL DEFAULT 'USER',
    "externalId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "places_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "places_on_trip" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "placeId" TEXT NOT NULL,
    "visitedAt" TIMESTAMP(3),
    "dayIndex" INTEGER,
    "notes" TEXT,
    "order" INTEGER,

    CONSTRAINT "places_on_trip_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "place_shares" (
    "id" TEXT NOT NULL,
    "placeId" TEXT NOT NULL,
    "tripId" TEXT,
    "threadEntryId" TEXT,
    "token" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "place_shares_pkey" PRIMARY KEY ("id")
);

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
CREATE UNIQUE INDEX "places_externalId_key" ON "places"("externalId");

-- CreateIndex
CREATE INDEX "places_lat_lng_idx" ON "places"("lat", "lng");

-- CreateIndex
CREATE UNIQUE INDEX "places_on_trip_tripId_placeId_visitedAt_key" ON "places_on_trip"("tripId", "placeId", "visitedAt");

-- CreateIndex
CREATE UNIQUE INDEX "place_shares_token_key" ON "place_shares"("token");

-- CreateIndex
CREATE UNIQUE INDEX "trip_join_requests_tripId_receiverId_key" ON "trip_join_requests"("tripId", "receiverId");

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_startLocationId_fkey" FOREIGN KEY ("startLocationId") REFERENCES "places"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_endLocationId_fkey" FOREIGN KEY ("endLocationId") REFERENCES "places"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_thread_entries" ADD CONSTRAINT "trip_thread_entries_placeId_fkey" FOREIGN KEY ("placeId") REFERENCES "places"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "places_on_trip" ADD CONSTRAINT "places_on_trip_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "places_on_trip" ADD CONSTRAINT "places_on_trip_placeId_fkey" FOREIGN KEY ("placeId") REFERENCES "places"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "place_shares" ADD CONSTRAINT "place_shares_placeId_fkey" FOREIGN KEY ("placeId") REFERENCES "places"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "place_shares" ADD CONSTRAINT "place_shares_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "place_shares" ADD CONSTRAINT "place_shares_threadEntryId_fkey" FOREIGN KEY ("threadEntryId") REFERENCES "trip_thread_entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "place_shares" ADD CONSTRAINT "place_shares_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_join_requests" ADD CONSTRAINT "trip_join_requests_tripId_fkey" FOREIGN KEY ("tripId") REFERENCES "trips"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_join_requests" ADD CONSTRAINT "trip_join_requests_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trip_join_requests" ADD CONSTRAINT "trip_join_requests_receiverId_fkey" FOREIGN KEY ("receiverId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

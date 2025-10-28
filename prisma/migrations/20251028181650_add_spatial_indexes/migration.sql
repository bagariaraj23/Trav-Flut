-- CreateIndex
CREATE INDEX "external_id_idx" ON "places"("externalId");

-- CreateIndex
CREATE INDEX "trip_visits_idx" ON "places_on_trip"("tripId", "visitedAt");

-- RenameIndex
ALTER INDEX "places_lat_lng_idx" RENAME TO "coordinate_spatial_idx";

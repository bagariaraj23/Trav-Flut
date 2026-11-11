-- Additive indexes for my-trips, media quota, invites, and chat list.
-- Does not rewrite or drop rows.

CREATE INDEX "trips_userId_createdAt_idx" ON "trips"("userId", "createdAt" DESC);

CREATE INDEX "media_tripId_idx" ON "media"("tripId");

CREATE INDEX "trip_join_requests_receiverId_status_idx" ON "trip_join_requests"("receiverId", "status");

CREATE INDEX "conversations_updatedAt_idx" ON "conversations"("updatedAt" DESC);

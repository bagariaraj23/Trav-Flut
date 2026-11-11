-- Indexes for feed, thread, notification, follow, and scheduler lookups.
-- Replaces narrower indexes where the new composite is a superset.

DROP INDEX IF EXISTS "notifications_recipientId_createdAt_idx";
CREATE INDEX "notifications_recipientId_createdAt_id_idx" ON "notifications"("recipientId", "createdAt" DESC, "id" DESC);

DROP INDEX IF EXISTS "Like_userId_idx";
CREATE INDEX "Like_userId_createdAt_idx" ON "Like"("userId", "createdAt" DESC);

DROP INDEX IF EXISTS "Comment_parentCommentId_idx";
CREATE INDEX "Comment_parentCommentId_createdAt_idx" ON "Comment"("parentCommentId", "createdAt" DESC);

CREATE INDEX "follows_followeeId_idx" ON "follows"("followeeId");

CREATE INDEX "follow_requests_followeeId_status_createdAt_idx" ON "follow_requests"("followeeId", "status", "createdAt" DESC);

CREATE INDEX "trips_userId_status_idx" ON "trips"("userId", "status");
CREATE INDEX "trips_status_endDate_idx" ON "trips"("status", "endDate");
CREATE INDEX "trips_status_startDate_idx" ON "trips"("status", "startDate");

CREATE INDEX "trip_participants_userId_idx" ON "trip_participants"("userId");

CREATE INDEX "trip_thread_entries_tripId_createdAt_id_idx" ON "trip_thread_entries"("tripId", "createdAt" DESC, "id" DESC);
CREATE INDEX "trip_thread_entries_authorId_createdAt_idx" ON "trip_thread_entries"("authorId", "createdAt" DESC);

CREATE INDEX "trip_final_posts_isPublished_createdAt_id_idx" ON "trip_final_posts"("isPublished", "createdAt" DESC, "id" DESC);

CREATE INDEX "media_uploadedById_createdAt_idx" ON "media"("uploadedById", "createdAt" DESC);

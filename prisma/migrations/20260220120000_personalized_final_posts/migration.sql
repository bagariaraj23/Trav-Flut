-- Add participant ownership to final posts
ALTER TABLE "trip_final_posts"
ADD COLUMN "userId" TEXT;

-- Backfill existing final posts to the trip owner
UPDATE "trip_final_posts" tfp
SET "userId" = t."userId"
FROM "trips" t
WHERE tfp."tripId" = t."id"
  AND tfp."userId" IS NULL;

-- Replace old one-per-trip unique with per-participant unique
DROP INDEX IF EXISTS "trip_final_posts_tripId_key";

ALTER TABLE "trip_final_posts"
ADD CONSTRAINT "trip_final_posts_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "users"("id")
ON DELETE CASCADE
ON UPDATE CASCADE;

CREATE UNIQUE INDEX "trip_final_posts_tripId_userId_key"
ON "trip_final_posts"("tripId", "userId");

CREATE INDEX "trip_final_posts_tripId_idx"
ON "trip_final_posts"("tripId");

CREATE INDEX "trip_final_posts_userId_isPublished_publishedAt_idx"
ON "trip_final_posts"("userId", "isPublished", "publishedAt");

ALTER TABLE "trip_final_posts"
ALTER COLUMN "userId" SET NOT NULL;

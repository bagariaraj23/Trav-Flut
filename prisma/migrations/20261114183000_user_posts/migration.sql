-- Posts that are not attached to a trip, and the engagement type they use.
ALTER TYPE "EntityType" ADD VALUE 'USER_POST';

CREATE TABLE "user_posts" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "caption" TEXT NOT NULL,
    "media" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "locationName" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "placeId" TEXT,
    "isPublished" BOOLEAN NOT NULL DEFAULT true,
    "publishedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "likeCount" INTEGER NOT NULL DEFAULT 0,
    "commentCount" INTEGER NOT NULL DEFAULT 0,
    "shareCount" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "user_posts_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "user_posts_userId_isPublished_publishedAt_idx"
ON "user_posts"("userId", "isPublished", "publishedAt");

CREATE INDEX "user_posts_isPublished_createdAt_id_idx"
ON "user_posts"("isPublished", "createdAt" DESC, "id" DESC);

ALTER TABLE "user_posts"
ADD CONSTRAINT "user_posts_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "users"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "user_posts"
ADD CONSTRAINT "user_posts_placeId_fkey"
FOREIGN KEY ("placeId") REFERENCES "places"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

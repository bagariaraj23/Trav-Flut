-- Author-chosen home feed card layout for published final posts.
-- Additive: existing rows default to postcard.

CREATE TYPE "FinalPostTemplateChoice" AS ENUM ('postcard', 'map_first', 'thread_reel');

ALTER TABLE "trip_final_posts"
ADD COLUMN "templateChoice" "FinalPostTemplateChoice" NOT NULL DEFAULT 'postcard';

-- Unpublished final posts use one label, DRAFT. READY was the same unpublished post.
UPDATE "trip_final_posts"
SET "generationStatus" = 'DRAFT'
WHERE "generationStatus" = 'READY';

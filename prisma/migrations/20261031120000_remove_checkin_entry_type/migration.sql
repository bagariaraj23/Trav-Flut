-- Check-in used the same place fields as a location entry.
-- Relabel existing rows, then drop CHECKIN from the enum. No rows are deleted.

UPDATE "trip_thread_entries"
SET "type" = 'LOCATION'
WHERE "type" = 'CHECKIN';

CREATE TYPE "ThreadEntryType_new" AS ENUM ('TEXT', 'MEDIA', 'LOCATION');

ALTER TABLE "trip_thread_entries"
  ALTER COLUMN "type" TYPE "ThreadEntryType_new"
  USING ("type"::text::"ThreadEntryType_new");

DROP TYPE "ThreadEntryType";

ALTER TYPE "ThreadEntryType_new" RENAME TO "ThreadEntryType";

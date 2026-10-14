-- Open-ended trips keep a real start instant and a null end until the owner ends them.
ALTER TABLE "trips" ALTER COLUMN "endDate" DROP NOT NULL;

-- Zone label for the wall time that was chosen. Legacy date-only rows stay null.
ALTER TABLE "trips" ADD COLUMN "scheduleTimezone" TEXT;

-- Existing explicit types stay sticky. Unset types can still auto-promote.
ALTER TABLE "trips" ADD COLUMN "typeSetByUser" BOOLEAN NOT NULL DEFAULT false;
UPDATE "trips" SET "typeSetByUser" = true WHERE "type" IS NOT NULL;

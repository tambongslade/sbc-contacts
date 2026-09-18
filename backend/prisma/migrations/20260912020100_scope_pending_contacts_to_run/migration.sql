-- Tie a PENDING contact to the run that queued it, so an abandoned run can
-- take its queue back with it.
ALTER TABLE "synced_contacts" ADD COLUMN IF NOT EXISTS "syncRunId" UUID;
CREATE INDEX IF NOT EXISTS "synced_contacts_syncRunId_idx" ON "synced_contacts"("syncRunId");

-- Existing PENDING rows predate the link, so none of them can be reclaimed by
-- run. They are all orphans by construction: a row only stays PENDING when its
-- run never reported, and no run is in flight across a deploy. Clearing them is
-- what turns "156 en attente" back into the truth.
DELETE FROM "synced_contacts" WHERE "status" = 'PENDING';

-- Same for the runs that stranded them: still RUNNING with nothing left to do.
UPDATE "sync_runs"
   SET "status" = 'ABANDONED', "finishedAt" = COALESCE("finishedAt", NOW())
 WHERE "status" IN ('RUNNING', 'PENDING');

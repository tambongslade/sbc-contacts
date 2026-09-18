-- Alone in its own migration on purpose: Postgres will not let a new enum
-- value be USED in the same transaction that adds it, and the next migration
-- needs to write 'ABANDONED'.
ALTER TYPE "SyncRunStatus" ADD VALUE IF NOT EXISTS 'ABANDONED';

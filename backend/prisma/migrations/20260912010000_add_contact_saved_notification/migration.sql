-- "Qui m'a enregistré ?" (cahier §21): the person saved now learns about it.
-- AddedEvent rows were already being written; this is the type of the
-- notification that finally reads them.
ALTER TYPE "NotificationType" ADD VALUE IF NOT EXISTS 'CONTACT_SAVED';

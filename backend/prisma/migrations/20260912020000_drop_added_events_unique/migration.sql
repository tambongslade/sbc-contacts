-- "Qui m'a enregistré ?" is an append-only event log: a member can be saved,
-- removed, and saved again, and each save is a real event. The earlier unique
-- (actorId, targetMemberSbcId) index — added before the notification-based
-- design landed — would make the second save throw, so drop it.
DROP INDEX IF EXISTS "added_events_actorId_targetMemberSbcId_key";

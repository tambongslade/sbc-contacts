-- AlterEnum
ALTER TYPE "NotificationType" ADD VALUE 'ADDED_BY_CONTACT';

-- CreateIndex
CREATE UNIQUE INDEX "added_events_actorId_targetMemberSbcId_key" ON "added_events"("actorId", "targetMemberSbcId");

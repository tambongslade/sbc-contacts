-- AlterTable
ALTER TABLE "users" ADD COLUMN     "statusBoostOptIn" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "statusBoostSince" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "users_statusBoostOptIn_idx" ON "users"("statusBoostOptIn");


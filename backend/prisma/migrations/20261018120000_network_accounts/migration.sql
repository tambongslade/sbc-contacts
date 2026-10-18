-- SBC Network's own accounts: created in the app, no SBC account behind them.
CREATE TYPE "AccountOrigin" AS ENUM ('SBC', 'NETWORK');

ALTER TYPE "MemberSource" ADD VALUE 'NETWORK';

ALTER TABLE "users" ADD COLUMN "origin" "AccountOrigin" NOT NULL DEFAULT 'SBC';

CREATE INDEX "users_origin_phoneNumber_idx" ON "users"("origin", "phoneNumber");

-- SBC Data: fill the demands gaps (Data §C, §E, §timeout).

-- New request state: the cap of interested answers was reached (Data §C).
ALTER TYPE "RequestStatus" ADD VALUE IF NOT EXISTS 'LOCKED';

-- The requester is told when nobody answered in time.
ALTER TYPE "NotificationType" ADD VALUE IF NOT EXISTS 'REQUEST_NO_RESPONSE';

-- Atomic "max N interested answers" counter (Data §C).
ALTER TABLE "service_requests" ADD COLUMN "responseCount" INTEGER NOT NULL DEFAULT 0;

-- Predictive market analytics / unfulfilled-demand tracking (Data §E).
CREATE TABLE "search_analytics" (
    "id" UUID NOT NULL,
    "userId" UUID,
    "requestId" UUID,
    "term" TEXT NOT NULL,
    "profession" TEXT,
    "city" TEXT,
    "mode" "ServiceMode",
    "matchedVendorCount" INTEGER NOT NULL,
    "fulfilled" BOOLEAN NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "search_analytics_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "search_analytics_fulfilled_createdAt_idx" ON "search_analytics"("fulfilled", "createdAt");
CREATE INDEX "search_analytics_term_idx" ON "search_analytics"("term");

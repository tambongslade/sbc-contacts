-- CreateEnum
CREATE TYPE "ServiceMode" AS ENUM ('HOME', 'ON_SITE', 'ONLINE', 'DELIVERY');

-- CreateEnum
CREATE TYPE "RequestStatus" AS ENUM ('DRAFT', 'MATCHING', 'SENT', 'RESPONDED', 'SELECTED', 'COMPLETED', 'CANCELLED', 'NO_MATCH', 'NO_RESPONSE');

-- CreateEnum
CREATE TYPE "DispatchStatus" AS ENUM ('SENT', 'VIEWED', 'INTERESTED', 'QUESTION', 'UNAVAILABLE', 'DECLINED', 'SELECTED', 'LOST');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "NotificationType" ADD VALUE 'REQUEST_RECEIVED';
ALTER TYPE "NotificationType" ADD VALUE 'REQUEST_RESPONSE';
ALTER TYPE "NotificationType" ADD VALUE 'REQUEST_SELECTED';
ALTER TYPE "NotificationType" ADD VALUE 'REQUEST_CLOSED';

-- CreateTable
CREATE TABLE "pro_profiles" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "profession" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "zones" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "modes" "ServiceMode"[] DEFAULT ARRAY[]::"ServiceMode"[],
    "availability" TEXT NOT NULL,
    "priceMin" INTEGER,
    "priceMax" INTEGER,
    "shopUrl" TEXT NOT NULL,
    "whatsapp" TEXT,
    "receivingEnabled" BOOLEAN NOT NULL DEFAULT false,
    "receivingUntil" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "pro_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pro_services" (
    "id" UUID NOT NULL,
    "proId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "profession" TEXT NOT NULL,
    "synonyms" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "specialties" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "description" TEXT,
    "priceMin" INTEGER,
    "priceMax" INTEGER,
    "modes" "ServiceMode"[] DEFAULT ARRAY[]::"ServiceMode"[],
    "zones" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "delay" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "embedding" DOUBLE PRECISION[] DEFAULT ARRAY[]::DOUBLE PRECISION[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "pro_services_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_requests" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "rawText" TEXT NOT NULL,
    "status" "RequestStatus" NOT NULL DEFAULT 'DRAFT',
    "profession" TEXT,
    "service" TEXT,
    "specialties" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "city" TEXT,
    "district" TEXT,
    "mode" "ServiceMode",
    "desiredDate" TEXT,
    "desiredTime" TEXT,
    "budget" INTEGER,
    "constraints" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "clarificationQuestion" TEXT,
    "clarificationOptions" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "clarificationAnswer" TEXT,
    "embedding" DOUBLE PRECISION[] DEFAULT ARRAY[]::DOUBLE PRECISION[],
    "selectedDispatchId" UUID,
    "sentAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "wasPerformed" BOOLEAN,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "request_dispatches" (
    "id" UUID NOT NULL,
    "requestId" UUID NOT NULL,
    "proId" UUID NOT NULL,
    "serviceId" UUID,
    "score" DOUBLE PRECISION NOT NULL,
    "reasons" JSONB,
    "status" "DispatchStatus" NOT NULL DEFAULT 'SENT',
    "price" INTEGER,
    "availability" TEXT,
    "delay" TEXT,
    "message" TEXT,
    "viewedAt" TIMESTAMP(3),
    "respondedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "request_dispatches_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "pro_profiles_userId_key" ON "pro_profiles"("userId");

-- CreateIndex
CREATE INDEX "pro_profiles_receivingEnabled_idx" ON "pro_profiles"("receivingEnabled");

-- CreateIndex
CREATE INDEX "pro_services_proId_isActive_idx" ON "pro_services"("proId", "isActive");

-- CreateIndex
CREATE INDEX "service_requests_userId_status_idx" ON "service_requests"("userId", "status");

-- CreateIndex
CREATE INDEX "request_dispatches_proId_status_idx" ON "request_dispatches"("proId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "request_dispatches_requestId_proId_key" ON "request_dispatches"("requestId", "proId");

-- AddForeignKey
ALTER TABLE "pro_profiles" ADD CONSTRAINT "pro_profiles_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pro_services" ADD CONSTRAINT "pro_services_proId_fkey" FOREIGN KEY ("proId") REFERENCES "pro_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_requests" ADD CONSTRAINT "service_requests_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "request_dispatches" ADD CONSTRAINT "request_dispatches_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "service_requests"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "request_dispatches" ADD CONSTRAINT "request_dispatches_proId_fkey" FOREIGN KEY ("proId") REFERENCES "pro_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "request_dispatches" ADD CONSTRAINT "request_dispatches_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "pro_services"("id") ON DELETE SET NULL ON UPDATE CASCADE;


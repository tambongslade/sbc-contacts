-- CreateEnum
CREATE TYPE "MessageAuthor" AS ENUM ('PRO', 'REQUESTER');

-- AlterEnum
ALTER TYPE "NotificationType" ADD VALUE 'REQUEST_MESSAGE';

-- CreateTable
CREATE TABLE "dispatch_messages" (
    "id" UUID NOT NULL,
    "dispatchId" UUID NOT NULL,
    "author" "MessageAuthor" NOT NULL,
    "text" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "dispatch_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "dispatch_messages_dispatchId_createdAt_idx" ON "dispatch_messages"("dispatchId", "createdAt");

-- AddForeignKey
ALTER TABLE "dispatch_messages" ADD CONSTRAINT "dispatch_messages_dispatchId_fkey" FOREIGN KEY ("dispatchId") REFERENCES "request_dispatches"("id") ON DELETE CASCADE ON UPDATE CASCADE;


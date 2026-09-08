-- CreateTable
CREATE TABLE "member_reviews" (
    "id" UUID NOT NULL,
    "reviewerUserId" UUID NOT NULL,
    "memberSbcId" TEXT NOT NULL,
    "stars" INTEGER NOT NULL,
    "comment" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "member_reviews_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "member_scores" (
    "memberSbcId" TEXT NOT NULL,
    "averageStars" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "reviewCount" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "member_scores_pkey" PRIMARY KEY ("memberSbcId")
);

-- CreateIndex
CREATE INDEX "member_reviews_memberSbcId_idx" ON "member_reviews"("memberSbcId");

-- CreateIndex
CREATE UNIQUE INDEX "member_reviews_reviewerUserId_memberSbcId_key" ON "member_reviews"("reviewerUserId", "memberSbcId");

-- AddForeignKey
ALTER TABLE "member_reviews" ADD CONSTRAINT "member_reviews_reviewerUserId_fkey" FOREIGN KEY ("reviewerUserId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

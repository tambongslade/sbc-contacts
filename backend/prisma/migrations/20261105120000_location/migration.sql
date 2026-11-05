-- "Près de moi": a pro's live position and where a requester asked from.
ALTER TABLE "pro_profiles" ADD COLUMN "latitude" DOUBLE PRECISION;
ALTER TABLE "pro_profiles" ADD COLUMN "longitude" DOUBLE PRECISION;
ALTER TABLE "pro_profiles" ADD COLUMN "locatedAt" TIMESTAMP(3);

ALTER TABLE "service_requests" ADD COLUMN "latitude" DOUBLE PRECISION;
ALTER TABLE "service_requests" ADD COLUMN "longitude" DOUBLE PRECISION;

-- The SBC Shop link is optional on a pro profile.
ALTER TABLE "pro_profiles" ALTER COLUMN "shopUrl" DROP NOT NULL;

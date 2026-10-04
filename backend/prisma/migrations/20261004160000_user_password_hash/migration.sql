-- Optional local password for the admin back-office (SSO stays the default).
ALTER TABLE "users" ADD COLUMN "passwordHash" TEXT;

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Seed placeholder. Phase 2+ will seed reference data (e.g. a demo user linked
 * to a test SBC account) here. Kept intentionally minimal for Phase 1.
 */
async function main(): Promise<void> {
  // eslint-disable-next-line no-console
  console.log('Nothing to seed yet (Phase 1). Add reference data in later phases.');
}

main()
  .catch((e) => {
    // eslint-disable-next-line no-console
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

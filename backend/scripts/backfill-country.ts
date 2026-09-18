/**
 * One-off backfill: stamp `country` onto mirror members that have none, from
 * their région (the `city` column). SBC's search never sent a country, so rows
 * mirrored before the ingest fix hold an empty country and no "Pays" criterion
 * matched them directly. New ingests derive country automatically; this reaches
 * the rows already in the mirror.
 *
 * Uses countryForRegion(), so it stamps ONLY régions/villes that belong to a
 * single country — the accent- and case-folding catches every spelling SBC
 * typed ("Yaoundé"/"Yaounde"/"YAOUNDÉ"). Genuinely shared names ("Centre",
 * "Littoral") are left NULL on purpose and matched by the query-time widening.
 *
 * Idempotent. Run with: npx ts-node scripts/backfill-country.ts
 */
import { PrismaClient } from '@prisma/client';
import { countryForRegion } from '../src/common/utils/region-country';

async function main(): Promise<void> {
  const prisma = new PrismaClient();
  try {
    const members = await prisma.member.findMany({
      where: { OR: [{ country: null }, { country: '' }] },
      select: { id: true, city: true },
    });
    console.log(`Members with empty country: ${members.length}`);

    const byCountry = new Map<string, string[]>();
    let unresolved = 0;
    for (const m of members) {
      const iso = countryForRegion(m.city);
      if (!iso) {
        unresolved++;
        continue;
      }
      (byCountry.get(iso) ?? byCountry.set(iso, []).get(iso)!).push(m.id);
    }

    let updated = 0;
    for (const [country, ids] of Array.from(byCountry.entries()).sort()) {
      const res = await prisma.member.updateMany({
        where: { id: { in: ids } },
        data: { country },
      });
      updated += res.count;
      console.log(`  ${country}: ${res.count}`);
    }

    console.log(
      `Backfilled ${updated} member(s); ${unresolved} left empty ` +
        `(région shared between countries, unknown, or absent — matched at query time).`,
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

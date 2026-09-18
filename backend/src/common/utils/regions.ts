import { toIsoCountry } from './country';

/** One région of one country, with how many mirrored members live there. */
export interface RegionEntry {
  country: string; // ISO alpha-2
  region: string;
  count: number;
}

/** A raw `(country, city)` group from the member mirror. */
export interface RegionGroupRow {
  country: string | null;
  city: string | null;
  count: number;
}

/** Case-, accent- and spacing-insensitive key for one région name. */
function foldRegion(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Turns mirror groups into the régions list the app offers per country.
 *
 * SBC stores `region` as typed, so the same place arrives as "Littoral",
 * "littoral " and "LITTORAL", and the country as a code or a display name.
 * Both are folded here: spellings of one région merge, their counts add up,
 * and the spelling kept is the most frequent one — the one most rows carry,
 * so a saved criterion using it matches the most members.
 */
export function aggregateRegions(rows: RegionGroupRow[]): RegionEntry[] {
  const merged = new Map<string, { country: string; counts: Map<string, number>; total: number }>();

  for (const row of rows) {
    const country = toIsoCountry(row.country)?.toUpperCase();
    const name = row.city?.replace(/\s+/g, ' ').trim();
    if (!country || !/^[A-Z]{2}$/.test(country) || !name || row.count <= 0) continue;

    const key = `${country}|${foldRegion(name)}`;
    const entry = merged.get(key) ?? { country, counts: new Map<string, number>(), total: 0 };
    entry.counts.set(name, (entry.counts.get(name) ?? 0) + row.count);
    entry.total += row.count;
    merged.set(key, entry);
  }

  return Array.from(merged.values())
    .map(({ country, counts, total }) => {
      const [region] = Array.from(counts.entries()).sort(
        (a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'fr'),
      )[0];
      return { country, region, count: total };
    })
    .sort(
      (a, b) =>
        a.country.localeCompare(b.country) ||
        b.count - a.count ||
        a.region.localeCompare(b.region, 'fr'),
    );
}

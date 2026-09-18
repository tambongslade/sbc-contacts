/**
 * Which country a SBC région belongs to.
 *
 * SBC's contact search returns no country at all — `normalizeContact` looks for
 * `country`/`pays` and finds neither — so the mirror's country column is empty
 * for almost every member, and a criteria asking for "Pays: Cameroun" matches
 * the handful of rows that got a country from somewhere else. The région is the
 * only location SBC does send, so it is what country has to be derived from.
 *
 * Several régions are genuinely shared: "Centre" is Cameroon and Burkina Faso,
 * "Littoral" is Cameroon and Benin. Those resolve to nothing here rather than
 * to a guess — see `countryForRegion`.
 */
const REGION_COUNTRIES: Record<string, string[]> = {
  Centre: ['CM', 'BF'],
  Maritime: ['TG'],
  Littoral: ['CM', 'BJ'],
  Abidjan: ['CI'],
  Ouest: ['CM'],
  Atlantique: ['BJ'],
  Plateaux: ['TG'],
  Brazzaville: ['CG'],
  Ouémé: ['BJ'],
  Kara: ['TG'],
  'Pointe-Noire': ['CG'],
  Borgou: ['BJ'],
  "N'Djamena": ['TD'],
  Centrale: ['TG'],
  Dakar: ['SN'],
  Est: ['CM', 'BF'],
  'Hauts-Bassins': ['BF'],
  Estuaire: ['GA'],
  Niamey: ['NE'],
  Nord: ['CM', 'BF'],
  Zou: ['BJ'],
  Savanes: ['TG', 'CI', 'BF'],
  Sud: ['CM'],
  Mono: ['BJ'],
  'Bas-Sassandra': ['CI'],
  'Centre-Ouest': ['BF'],
  Adamaoua: ['CM'],
  Bamako: ['ML'],
  Plateau: ['BJ'],
  Couffo: ['BJ'],
  Yamoussoukro: ['CI'],
  'Extrême-Nord': ['CM'],
  Comoé: ['CI'],
  Lagunes: ['CI'],
  Collines: ['BJ'],
  'Sud-Ouest': ['CM', 'BF'],
  'Centre-Est': ['BF'],
  'Boucle du Mouhoun': ['BF'],
  Kadiogo: ['BF'],
  Atacora: ['BJ'],
  Alibori: ['BJ'],
  'Sassandra-Marahoué': ['CI'],
  Donga: ['BJ'],
  'Vallée du Bandama': ['CI'],
  'Gôh-Djiboua': ['CI'],
  'Ogooué-Maritime': ['GA'],
  'Chari-Baguirmi': ['TD'],
  Montagnes: ['CI'],
  Kinshasa: ['CD'],
  Zinder: ['NE'],
  'Centre-Nord': ['BF'],
  Zanzan: ['CI'],
  Bangui: ['CF'],
  'Haut-Katanga': ['CD'],
  'Haut-Ogooué': ['GA'],
  Congo: ['CD'],
  Ouaddaï: ['TD'],
  Thiès: ['SN'],
  'Mayo-Kebbi Est': ['TD'],
  'Logone Occidental': ['TD'],
};

/** Case-, accent- and spacing-insensitive key, as SBC types régions freely. */
function fold(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

const BY_FOLDED = new Map<string, string[]>(
  Object.entries(REGION_COUNTRIES).map(([region, codes]) => [fold(region), codes]),
);

/**
 * The country a région belongs to, or undefined when it belongs to more than
 * one (or is unknown).
 *
 * Deliberately refuses to guess. Writing "CM" onto every "Centre" would put
 * Burkinabè members into Cameroonian criteria, and a criteria that quietly
 * returns the wrong people is worse than one that returns fewer: the member
 * saves those contacts to their phone.
 */
export function countryForRegion(region?: string | null): string | undefined {
  if (!region) return undefined;
  const codes = BY_FOLDED.get(fold(region));
  return codes?.length === 1 ? codes[0] : undefined;
}

/**
 * Every région that belongs to this country, including the shared ones.
 *
 * Used to widen a country criteria over members whose country could not be
 * derived: asking for Cameroon, "Littoral" is a Cameroonian région, and the
 * alternative is missing every member in Douala. The widening only ever applies
 * to rows with no country of their own, so it cannot overrule real data.
 */
export function regionsForCountry(code?: string | null): string[] {
  if (!code) return [];
  const iso = code.toUpperCase();
  return Object.entries(REGION_COUNTRIES)
    .filter(([, codes]) => codes.includes(iso))
    .map(([region]) => region);
}

/** The régions that resolve to exactly one country — what a backfill can use. */
export function unambiguousRegions(): Array<{ region: string; country: string }> {
  return Object.entries(REGION_COUNTRIES)
    .filter(([, codes]) => codes.length === 1)
    .map(([region, codes]) => ({ region, country: codes[0] }));
}

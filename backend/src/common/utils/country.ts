/**
 * One country vocabulary, shared by everything that reads or writes a country.
 *
 * SBC's search *parameter* is an ISO alpha-2 code, but the member records it
 * returns carry the country however it was typed ("Cameroun", "cameroon", and
 * occasionally the code). Normalising only the outgoing query — which is what
 * used to happen — left the mirror holding names while saved criteria matched
 * on codes, so "Pays: Cameroun" counted 2 members out of the several hundred
 * actually mirrored from Cameroon.
 */
const COUNTRY_ISO: Record<string, string> = {
  cameroun: 'CM',
  cameroon: 'CM',
  'cote divoire': 'CI',
  'cote d ivoire': 'CI',
  'ivory coast': 'CI',
  senegal: 'SN',
  togo: 'TG',
  benin: 'BJ',
  congo: 'CG',
  'congo brazzaville': 'CG',
  'republique du congo': 'CG',
  rdc: 'CD',
  'congo kinshasa': 'CD',
  'republique democratique du congo': 'CD',
  tchad: 'TD',
  chad: 'TD',
  niger: 'NE',
  mali: 'ML',
  'burkina faso': 'BF',
  burkina: 'BF',
  gabon: 'GA',
  centrafrique: 'CF',
  'republique centrafricaine': 'CF',
  guinee: 'GN',
  guinea: 'GN',
  mauritanie: 'MR',
  france: 'FR',
  belgique: 'BE',
  belgium: 'BE',
  canada: 'CA',
  'etats unis': 'US',
  'united states': 'US',
  usa: 'US',
};

/** Lower-case, accent-free, punctuation-free form used as the lookup key. */
function fold(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** ISO alpha-2 for a country written any of the ways SBC writes it. */
export function toIsoCountry(input?: string | null): string | undefined {
  if (!input) return input ?? undefined;
  const key = fold(input);
  if (COUNTRY_ISO[key]) return COUNTRY_ISO[key];
  // Already a code (the common case once ingest normalises).
  if (/^[a-z]{2}$/.test(key)) return key.toUpperCase();
  return input;
}

/**
 * Every spelling a country may appear as in the mirror, given one ISO code.
 *
 * Rows written before ingest normalised still hold the display name, and a
 * backfill cannot reach rows SBC has not re-sent yet. Matching on the whole
 * alias set means saved criteria work on today's data instead of only on data
 * mirrored from now on.
 */
export function countryAliases(code: string): string[] {
  const iso = toIsoCountry(code) ?? code;
  const names = Object.entries(COUNTRY_ISO)
    .filter(([, v]) => v === iso)
    .map(([k]) => k);
  const cased = names.flatMap((n) => {
    const title = n.replace(/\b[a-z]/g, (c) => c.toUpperCase());
    return [n, title];
  });
  return Array.from(new Set([iso, iso.toLowerCase(), ...cased]));
}

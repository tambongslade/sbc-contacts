/**
 * International dialing codes for the countries the app offers, so an SBC
 * Network account's WhatsApp number is stored the way `wa.me` wants it: digits
 * only, country code first ("237670000000").
 */
export const DIAL_CODES: Record<string, string> = {
  CM: '237',
  CI: '225',
  TG: '228',
  BJ: '229',
  CG: '242',
  CD: '243',
  SN: '221',
  GA: '241',
  NE: '227',
  ML: '223',
  BF: '226',
  TD: '235',
  CF: '236',
  GN: '224',
  FR: '33',
  BE: '32',
  CA: '1',
  US: '1',
};

/**
 * A WhatsApp number in international digits, or null when it cannot be one.
 * Accepts it typed with or without the country code ("+237 6 70…", "670…",
 * "0612…" in France).
 */
export function toInternationalPhone(raw: string, country?: string | null): string | null {
  const typed = raw.trim();
  let digits = typed.replace(/\D/g, '');
  if (typed.startsWith('00')) digits = digits.slice(2);
  const dial = country ? DIAL_CODES[country.toUpperCase()] : undefined;
  const international = typed.startsWith('+') || typed.startsWith('00');
  if (!international && dial && !digits.startsWith(dial)) {
    digits = dial + digits.replace(/^0+/, '');
  }
  return digits.length >= 8 && digits.length <= 15 ? digits : null;
}

/**
 * Who may filter the "Augmenter mes vues WhatsApp" list, and by what. The SBC
 * subscription decides: Ciblé filters by everything a criteria can, anyone
 * else (Classique, or none) by country only.
 */
export type FilterAccess = 'all' | 'country';

/** The criteria filters, as the list and its criteria take them. */
export interface BoostFilters {
  countries?: string[];
  cities?: string[];
  professions?: string[];
  interests?: string[];
  sex?: string | null;
  ageMin?: number | null;
  ageMax?: number | null;
}

export const ADVANCED_FILTERS_MESSAGE =
  "Seul le pays est disponible avec ton abonnement : les autres filtres demandent l'abonnement Ciblé";

export function filterAccessFor(subscriptionTypes: string[]): FilterAccess {
  return subscriptionTypes.some((t) => t.toUpperCase() === 'CIBLE') ? 'all' : 'country';
}

export function hasFilters(f: BoostFilters): boolean {
  return Boolean(f.countries?.length) || hasAdvancedFilters(f);
}

/** Any filter besides the country. */
export function hasAdvancedFilters(f: BoostFilters): boolean {
  return (
    Boolean(f.cities?.length) ||
    Boolean(f.professions?.length) ||
    Boolean(f.interests?.length) ||
    Boolean(f.sex) ||
    f.ageMin != null ||
    f.ageMax != null
  );
}

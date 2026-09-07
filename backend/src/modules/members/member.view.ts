/** Canonical member representation returned to clients across modules. */
export interface MemberView {
  id: string; // our local uuid
  sbcId: string;
  name: string | null;
  firstName: string | null;
  profession: string | null;
  city: string | null;
  country: string | null;
  sex: string | null;
  age: number | null;
  interests: string[];
  skills: string[];
  avatarUrl: string | null;
  phoneNumber: string | null;
  isFavorite: boolean;
  isSynced: boolean;
}

/** Criteria shape shared by SyncCriteria rows and ad-hoc previews. */
export interface MatchCriteria {
  countries: string[];
  cities: string[];
  professions: string[];
  interests: string[];
  sex?: string | null;
  ageMin?: number | null;
  ageMax?: number | null;
}

/** Map a persisted SyncCriteria row to the matcher's criteria shape. */
export function toMatchCriteria(c: {
  countries: string[];
  cities: string[];
  professions: string[];
  interests: string[];
  sex: string | null;
  ageMin: number | null;
  ageMax: number | null;
}): MatchCriteria {
  return {
    countries: c.countries,
    cities: c.cities,
    professions: c.professions,
    interests: c.interests,
    sex: c.sex,
    ageMin: c.ageMin,
    ageMax: c.ageMax,
  };
}

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
  // Reputation ("Score de confiance"). Neutral 50 when unrated.
  confidenceScore: number;
  averageRating: number | null;
  reviewCount: number;
  myRating: number | null; // the caller's own star rating, if any
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
  /**
   * Only these members. Set for a "Augmenter mes vues WhatsApp" criteria, whose
   * members are a list we hold rather than a filter SBC can search; empty
   * matches nobody.
   */
  sbcIds?: string[] | null;
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
  statusBoost?: boolean;
}): MatchCriteria {
  return {
    countries: c.countries,
    cities: c.cities,
    professions: c.professions,
    interests: c.interests,
    sex: c.sex,
    ageMin: c.ageMin,
    ageMax: c.ageMax,
    // Its filters are empty, so on their own they would match every member.
    // Until the participants are resolved (CriteriaMatchResolver), match none.
    ...(c.statusBoost ? { sbcIds: [] } : {}),
  };
}

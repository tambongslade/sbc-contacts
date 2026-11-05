/** Shapes returned by SBC's SSO endpoints (see SSO_INTEGRATION_GUIDE.md). */

export interface SbcUser {
  id: string;
  name: string;
  email: string;
  phoneNumber: string;
  country: string;
  avatarUrl: string;
  /** The member's ACTIVE subscriptions, by type: CLASSIQUE, CIBLE, PRO, MISE_EN_AVANT. */
  subscriptionTypes: string[];
  /**
   * The same subscriptions with their dates (see docs/paiements-sbc.md). Optional
   * until SBC sends it; without it a paid feature lasts as long as its type
   * stays in `subscriptionTypes`.
   */
  subscriptions?: SbcSubscription[];
  directReferralCount?: number;
  isActivated: boolean;
}

/** One paid subscription as SBC reports it. */
export interface SbcSubscription {
  /** CLASSIQUE | CIBLE | PRO | MISE_EN_AVANT */
  type: string;
  /** active | expired | cancelled */
  status: string;
  /** ISO 8601 */
  startedAt?: string | null;
  /** ISO 8601 — the end of the paid period. */
  expiresAt?: string | null;
}

export interface SbcTokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: 'Bearer';
  expires_in: number; // seconds
  scope: string;
  user: SbcUser;
}

export interface SbcRefreshResponse {
  access_token: string;
  refresh_token: string;
  token_type: 'Bearer';
  expires_in: number;
  scope: string;
}

/** SBC always wraps payloads in { success, data }. */
export interface SbcEnvelope<T> {
  success: boolean;
  data: T;
  message?: string;
  code?: string; // e.g. SUBSCRIPTION_REQUIRED, INSUFFICIENT_SCOPE
}

/**
 * A single member as returned by SBC's contacts search. The exact field names of
 * the first-party endpoint aren't published, so the client normalises several
 * plausible aliases (fr/en) into this stable shape — see normalizeContact().
 */
export interface SbcContact {
  id: string;
  name?: string;
  firstName?: string;
  profession?: string;
  city?: string;
  country?: string;
  sex?: string;
  age?: number;
  interests?: string[];
  skills?: string[];
  avatarUrl?: string;
  phoneNumber?: string;
}

/** Normalised, paginated contacts search result. */
export interface SbcSearchData {
  items: SbcContact[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
  hasMore: boolean;
}

/** Query params accepted by the contacts search (subset SBC supports). */
export interface SbcContactQuery {
  search?: string;
  country?: string;
  region?: string;
  city?: string;
  profession?: string;
  sex?: string;
  ageMin?: number;
  ageMax?: number;
  interests?: string[];
  page?: number;
  limit?: number;
}

export interface SbcExportResult {
  body: string;
  contentType: string;
  filename: string;
}

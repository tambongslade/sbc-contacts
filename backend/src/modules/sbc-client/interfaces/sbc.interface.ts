/** Shapes returned by SBC's SSO endpoints (see SSO_INTEGRATION_GUIDE.md). */

export interface SbcUser {
  id: string;
  name: string;
  email: string;
  phoneNumber: string;
  country: string;
  avatarUrl: string;
  subscriptionTypes: string[];
  directReferralCount?: number;
  isActivated: boolean;
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

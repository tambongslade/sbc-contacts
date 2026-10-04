import { api, tokens, type Tokens } from './api';

/** SBC "Log in with SBC", through the backend's registered redirect_uri. */
const AUTHORIZE = 'https://sniperbuisnesscenter.com/sso/authorize';
const CLIENT_ID = 'sbc-contacts';
const REDIRECT_URI = 'https://contacts.sniperbusinesscenterlive.com/auth/callback';
const SCOPES = 'profile.read contacts.read';
const STATE_KEY = 'sbcAdmin.state';

export interface AdminUser {
  id: string;
  name: string | null;
  email: string | null;
  role: 'USER' | 'ADMIN' | 'SUPER_ADMIN';
}

export const isAdmin = (u: AdminUser | null) => u?.role === 'ADMIN' || u?.role === 'SUPER_ADMIN';

/**
 * Off to SBC. The state carries an "admin." prefix: the backend's callback
 * page sees it and sends the code back here instead of to the mobile app.
 */
export function startLogin() {
  const state = `admin.${crypto.randomUUID()}`;
  sessionStorage.setItem(STATE_KEY, state);
  const url = new URL(AUTHORIZE);
  url.search = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    scope: SCOPES,
    state,
  }).toString();
  window.location.assign(url.toString());
}

/** Finishes a login when SBC sent us back with ?code=…&state=…. */
export async function completeLoginFromUrl(): Promise<AdminUser | null> {
  const params = new URLSearchParams(window.location.search);
  const code = params.get('code');
  const state = params.get('state');
  if (!code) return null;
  window.history.replaceState(null, '', window.location.pathname + window.location.hash);
  const expected = sessionStorage.getItem(STATE_KEY);
  sessionStorage.removeItem(STATE_KEY);
  if (!state || state !== expected) throw new Error('La connexion a expiré, recommence.');
  const result = await api<{ user: AdminUser; tokens: Tokens }>('/auth/sso-callback', {
    method: 'POST',
    body: { code, redirectUri: REDIRECT_URI },
  });
  tokens.set(result.tokens);
  return result.user;
}

/**
 * Local development only: `?devToken=<jwt>` signs in with a token minted for
 * a test admin against a local backend. Stripped from production builds.
 */
export function applyDevToken() {
  if (!import.meta.env.DEV) return;
  const t = new URLSearchParams(window.location.search).get('devToken');
  if (!t) return;
  tokens.set({ accessToken: t, refreshToken: '' });
  window.history.replaceState(null, '', window.location.pathname + window.location.hash);
}

export function currentUser() {
  return api<AdminUser>('/auth/me');
}

export async function logout() {
  const t = tokens.get();
  if (t?.refreshToken) {
    await api('/auth/logout', { method: 'POST', body: { refreshToken: t.refreshToken } }).catch(() => {});
  }
  tokens.clear();
}

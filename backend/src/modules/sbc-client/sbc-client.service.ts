import {
  BadGatewayException,
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  SbcContact,
  SbcContactQuery,
  SbcEnvelope,
  SbcExportResult,
  SbcRefreshResponse,
  SbcSearchData,
  SbcTokenResponse,
  SbcUser,
} from './interfaces/sbc.interface';

/**
 * The ONLY place in the codebase that talks to SBC. Wraps the SSO endpoints
 * documented in SSO_INTEGRATION_GUIDE.md. `client_secret` never leaves here.
 * Network/protocol failures are normalised to clean HTTP exceptions so callers
 * never see raw fetch errors (brief §8, §16-external-services).
 */
@Injectable()
export class SbcClientService {
  private readonly logger = new Logger(SbcClientService.name);
  private readonly baseUrl: string;
  private readonly clientId: string;
  private readonly clientSecret: string;
  private readonly redirectUri: string;
  private static readonly TIMEOUT_MS = 10_000;

  constructor(config: ConfigService) {
    this.baseUrl = config.get<string>('sbc.baseUrl')!.replace(/\/$/, '');
    this.clientId = config.get<string>('sbc.clientId')!;
    this.clientSecret = config.get<string>('sbc.clientSecret')!;
    this.redirectUri = config.get<string>('sbc.redirectUri')!;
  }

  /** Exchange a one-shot authorization code for SBC tokens + user profile. */
  async exchangeCode(code: string): Promise<SbcTokenResponse> {
    return this.post<SbcTokenResponse>('/api/sso/token', {
      code,
      client_id: this.clientId,
      client_secret: this.clientSecret,
      redirect_uri: this.redirectUri,
    });
  }

  /** Rotate an SBC access token using the (rolling) refresh token. */
  async refresh(refreshToken: string): Promise<SbcRefreshResponse> {
    return this.post<SbcRefreshResponse>('/api/sso/refresh', {
      refresh_token: refreshToken,
      client_id: this.clientId,
      client_secret: this.clientSecret,
    });
  }

  /** Fresh profile for the token owner (subscription state can change). */
  async getUserInfo(accessToken: string): Promise<SbcUser> {
    const data = await this.get<{ user?: SbcUser } | SbcUser>('/api/sso/userinfo', accessToken);
    // Guide returns the user shape directly under `data`; tolerate a nested form.
    return (data as { user?: SbcUser }).user ?? (data as SbcUser);
  }

  /**
   * The member's own contact list (cahier §6/§7), scoped to their subscription.
   * `contacts.read` scope + active subscription required — 403s carry a `code`.
   */
  async searchContacts(accessToken: string, query: SbcContactQuery): Promise<SbcSearchData> {
    const raw = await this.get<Record<string, unknown>>(
      `/api/contacts/sso/search${this.buildQuery(query)}`,
      accessToken,
    );
    const normalized = this.normalizeSearch(raw, query);
    const firstUser = Array.isArray((raw as { users?: unknown[] }).users)
      ? (raw as { users: Array<Record<string, unknown>> }).users[0]
      : undefined;
    this.logger.log(
      `contacts/sso/search keys=[${Object.keys(raw ?? {}).join(',')}]` +
        ` memberKeys=[${firstUser ? Object.keys(firstUser).join(',') : ''}]` +
        ` -> ${normalized.items.length} items (total ${normalized.total})`,
    );
    return normalized;
  }

  /** The same list as a downloadable VCF (cahier §9). */
  async exportContacts(accessToken: string, query: SbcContactQuery): Promise<SbcExportResult> {
    const res = await this.fetchWithTimeout(
      `${this.baseUrl}/api/contacts/sso/export${this.buildQuery(query)}`,
      { method: 'GET', headers: { Authorization: `Bearer ${accessToken}` } },
    );
    if (!res.ok) {
      await this.throwForStatus(res, '/api/contacts/sso/export');
    }
    return {
      body: await res.text(),
      contentType: res.headers.get('content-type') ?? 'text/vcard; charset=utf-8',
      filename: 'sbc-contacts.vcf',
    };
  }

  // ── internals ──────────────────────────────────────────────

  private async post<T>(path: string, body: Record<string, unknown>): Promise<T> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return this.unwrap<T>(res, path);
  }

  private async get<T>(path: string, accessToken: string): Promise<T> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}${path}`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    return this.unwrap<T>(res, path);
  }

  private async fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), SbcClientService.TIMEOUT_MS);
    try {
      return await fetch(url, { ...init, signal: controller.signal });
    } catch (err) {
      this.logger.error(`SBC request failed: ${(err as Error).name}`);
      throw new ServiceUnavailableException('SBC service is unreachable');
    } finally {
      clearTimeout(timer);
    }
  }

  private async unwrap<T>(res: Response, path: string): Promise<T> {
    let payload: (SbcEnvelope<T> & Record<string, unknown>) | undefined;
    try {
      payload = (await res.json()) as SbcEnvelope<T> & Record<string, unknown>;
    } catch {
      payload = undefined;
    }

    // Any 2xx is a success. SBC's SSO endpoints wrap payloads in { success, data },
    // but the contacts search (the first-party controller) returns its own shape.
    // Return `data` when present, otherwise the raw body — the caller normalises it.
    if (res.ok) {
      if (payload && typeof payload === 'object' && 'data' in payload && payload.success !== false) {
        return payload.data;
      }
      return payload as unknown as T;
    }

    this.mapError(res.status, path, payload?.message, payload?.code);
  }

  /** For non-JSON endpoints (export): map status without parsing a body. */
  private async throwForStatus(res: Response, path: string): Promise<never> {
    let code: string | undefined;
    let message: string | undefined;
    try {
      const body = (await res.json()) as SbcEnvelope<unknown>;
      code = body.code;
      message = body.message;
    } catch {
      /* non-JSON error body */
    }
    this.mapError(res.status, path, message, code);
  }

  private mapError(status: number, path: string, message?: string, code?: string): never {
    this.logger.warn(`SBC ${path} -> ${status} ${code ?? ''} ${message ?? ''}`.trim());
    switch (status) {
      case 400:
        throw new BadRequestException(message ?? 'Invalid SBC request');
      case 401:
        throw new UnauthorizedException('SBC authentication failed');
      case 403:
        // Preserve SBC's code (SUBSCRIPTION_REQUIRED / INSUFFICIENT_SCOPE) for the client.
        throw new ForbiddenException({
          message: message ?? 'SBC authorization failed',
          code: code ?? 'FORBIDDEN',
        });
      default:
        throw new BadGatewayException(
          `Unexpected response from SBC (status ${status})${message ? `: ${message}` : ''}`,
        );
    }
  }

  private buildQuery(query: SbcContactQuery): string {
    const params = new URLSearchParams();
    const add = (k: string, v: unknown) => {
      if (v === undefined || v === null || v === '') return;
      params.append(k, String(v));
    };
    add('search', query.search);
    add('country', query.country);
    add('city', query.city);
    add('profession', query.profession);
    add('sex', query.sex);
    add('ageMin', query.ageMin);
    add('ageMax', query.ageMax);
    add('page', query.page);
    add('limit', query.limit);
    (query.interests ?? []).forEach((i) => add('interests', i));
    const qs = params.toString();
    return qs ? `?${qs}` : '';
  }

  /**
   * Normalise SBC's (undocumented-shape) search payload into SbcSearchData.
   * Tolerates the list living under items/contacts/results, and fr/en field
   * aliases per contact, so a shape change on SBC's side degrades gracefully.
   */
  private normalizeSearch(raw: Record<string, unknown>, query: SbcContactQuery): SbcSearchData {
    const list =
      (raw.users as unknown[]) ?? // SBC's actual key for the member list
      (raw.items as unknown[]) ??
      (raw.contacts as unknown[]) ??
      (raw.results as unknown[]) ??
      (raw.data as unknown[]) ??
      (Array.isArray(raw) ? (raw as unknown[]) : []);

    const items = list.map((c) => this.normalizeContact(c as Record<string, unknown>));
    const page = Number(raw.page ?? query.page ?? 1);
    const limit = Number(raw.limit ?? raw.pageSize ?? query.limit ?? items.length ?? 20);
    const total = Number(raw.totalCount ?? raw.total ?? items.length); // SBC: totalCount
    const totalPages = Number(raw.totalPages ?? (limit ? Math.ceil(total / limit) : 0));
    const hasMore = raw.hasMore !== undefined ? Boolean(raw.hasMore) : page < totalPages;

    return { items, total, page, limit, totalPages, hasMore };
  }

  /**
   * Normalise a raw SBC contact (fr/en aliases) into our SbcContact shape.
   * Public so the webhook processor can reuse it — SBC's push payload uses the
   * same field names as its search, so both paths must normalise identically.
   */
  normalizeContact(c: Record<string, unknown>): SbcContact {
    const pick = (...keys: string[]): unknown => keys.map((k) => c[k]).find((v) => v != null);
    const asStrArr = (v: unknown): string[] | undefined =>
      Array.isArray(v) ? v.map(String) : undefined;
    const id = pick('id', '_id');
    return {
      id: id != null ? String(id) : '',
      name: pick('name', 'nom') as string | undefined,
      firstName: pick('firstName', 'prenom', 'prénom') as string | undefined,
      profession: pick('profession', 'metier', 'métier') as string | undefined,
      // SBC uses `region` for location (no city on list items).
      city: pick('city', 'ville', 'region', 'town') as string | undefined,
      country: pick('country', 'pays') as string | undefined,
      sex: pick('sex', 'sexe', 'gender') as string | undefined,
      age: pick('age') != null ? Number(pick('age')) : undefined,
      interests: asStrArr(pick('interests', 'centresInteret', 'centres_interet')),
      skills: asStrArr(pick('skills', 'competences', 'compétences')),
      avatarUrl: pick('avatarUrl', 'photo', 'avatar') as string | undefined,
      phoneNumber: pick('phoneNumber', 'phone', 'whatsapp', 'telephone') as string | undefined,
    };
  }
}

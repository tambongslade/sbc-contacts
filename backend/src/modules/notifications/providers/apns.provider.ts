import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createPrivateKey, KeyObject, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { ClientHttp2Session, connect, constants } from 'node:http2';
import { DevicesService } from '../devices.service';
import { NotificationPayload, NotificationProvider } from './notification-provider.interface';

/** APNs reasons meaning the token will never work again. */
const DEAD_TOKEN = new Set(['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic']);

/** Apple refuses a provider token older than an hour and throttles fresh ones. */
const TOKEN_TTL_MS = 50 * 60 * 1000;

/**
 * Push channel over the Apple Push Notification service: the native iOS app.
 *
 * Token-based auth (.p8 key, ES256 JWT) over HTTP/2, with no SDK. Config-gated
 * like the FCM provider: with no key it logs the dispatch and sends nothing.
 * Fails soft per device; tokens Apple reports dead are removed.
 */
@Injectable()
export class ApnsProvider implements NotificationProvider, OnModuleDestroy {
  readonly channel = 'apns';
  private readonly logger = new Logger(ApnsProvider.name);
  private readonly key: KeyObject | null;
  private readonly keyId: string;
  private readonly teamId: string;
  private readonly bundleId: string;
  private readonly host: string;
  private session: ClientHttp2Session | null = null;
  private jwt: { value: string; at: number } | null = null;

  constructor(
    config: ConfigService,
    private readonly devices: DevicesService,
  ) {
    this.keyId = config.get<string>('apns.keyId') ?? '';
    this.teamId = config.get<string>('apns.teamId') ?? '';
    this.bundleId = config.get<string>('apns.bundleId') || 'com.sbc.sbcContacts';
    this.host = config.get<boolean>('apns.production', true)
      ? 'https://api.push.apple.com'
      : 'https://api.sandbox.push.apple.com';

    let pem = config.get<string>('apns.key') ?? '';
    const path = config.get<string>('apns.keyPath') ?? '';
    if (!pem && path) {
      try {
        pem = readFileSync(path, 'utf8');
      } catch (err) {
        this.logger.error(`APNS_KEY_PATH unreadable (${path}): ${(err as Error).message}`);
      }
    }

    if (pem && this.keyId && this.teamId) {
      this.key = createPrivateKey(pem);
      this.logger.log(`APNs push enabled (${this.host}, topic ${this.bundleId})`);
    } else {
      this.key = null;
      this.logger.warn('APNs not configured — iOS pushes are logged, not sent');
    }
  }

  onModuleDestroy(): void {
    this.session?.close();
  }

  async send(payload: NotificationPayload): Promise<void> {
    if (payload.apnsTokens.length === 0) return;
    if (!this.key) {
      this.logger.log(
        `[apns:stub] -> ${payload.apnsTokens.length} device(s) | ${payload.type}: ${payload.title}`,
      );
      return;
    }

    const body = JSON.stringify({
      aps: {
        alert: { title: payload.title, body: payload.body },
        sound: 'default',
        badge: payload.badge,
        'thread-id': payload.type,
      },
      // Read by the app when the notification is tapped.
      link: payload.link,
      type: payload.type,
      notificationId: payload.notificationId,
    });

    const results = await Promise.all(
      payload.apnsTokens.map((token) => this.post(token, body, payload.notificationId)),
    );
    const failures = results.filter((r) => r.status !== 200);
    if (failures.length > 0) {
      this.logger.warn(
        `apns ${payload.type}: ${results.length - failures.length}/${results.length} delivered ` +
          `(failures: ${failures.map((f) => `${f.status} ${f.reason}`).join(', ')})`,
      );
    }
    await this.devices.forgetTokens(
      failures.filter((f) => DEAD_TOKEN.has(f.reason) || f.status === 410).map((f) => f.token),
    );
  }

  private post(
    token: string,
    body: string,
    collapseId: string,
  ): Promise<{ token: string; status: number; reason: string }> {
    return new Promise((resolve) => {
      let req;
      try {
        req = this.connection().request({
          [constants.HTTP2_HEADER_METHOD]: 'POST',
          [constants.HTTP2_HEADER_PATH]: `/3/device/${token}`,
          authorization: `bearer ${this.providerToken()}`,
          'apns-topic': this.bundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-collapse-id': collapseId.slice(0, 64),
          'content-type': 'application/json',
        });
      } catch (err) {
        resolve({ token, status: 0, reason: (err as Error).message });
        return;
      }
      let status = 0;
      let raw = '';
      req.setEncoding('utf8');
      req.setTimeout(10_000, () => req.close(constants.NGHTTP2_CANCEL));
      req.on('response', (headers) => (status = Number(headers[constants.HTTP2_HEADER_STATUS])));
      req.on('data', (chunk: string) => (raw += chunk));
      req.on('end', () => {
        let reason = '';
        try {
          reason = raw ? ((JSON.parse(raw) as { reason?: string }).reason ?? '') : '';
        } catch {
          reason = raw;
        }
        resolve({ token, status, reason });
      });
      req.on('error', (err) => resolve({ token, status: 0, reason: err.message }));
      req.end(body);
    });
  }

  /** One HTTP/2 connection, reopened when Apple or the network closes it. */
  private connection(): ClientHttp2Session {
    if (this.session && !this.session.closed && !this.session.destroyed) return this.session;
    const session = connect(this.host);
    session.on('error', (err) => this.logger.warn(`APNs connection error: ${err.message}`));
    session.on('close', () => {
      if (this.session === session) this.session = null;
    });
    session.unref();
    this.session = session;
    return session;
  }

  /** The ES256 provider token, reused for 50 minutes as Apple asks. */
  private providerToken(): string {
    const now = Date.now();
    if (this.jwt && now - this.jwt.at < TOKEN_TTL_MS) return this.jwt.value;
    const b64 = (v: object) => Buffer.from(JSON.stringify(v)).toString('base64url');
    const unsigned = `${b64({ alg: 'ES256', kid: this.keyId })}.${b64({
      iss: this.teamId,
      iat: Math.floor(now / 1000),
    })}`;
    const signature = sign('sha256', Buffer.from(unsigned), {
      key: this.key!,
      dsaEncoding: 'ieee-p1363',
    }).toString('base64url');
    this.jwt = { value: `${unsigned}.${signature}`, at: now };
    return this.jwt.value;
  }
}

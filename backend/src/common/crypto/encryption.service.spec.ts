import { ConfigService } from '@nestjs/config';
import { EncryptionService } from './encryption.service';

describe('EncryptionService', () => {
  const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const refreshSecret = 'unit-test-refresh-secret-at-least-32-chars';

  const build = () =>
    new EncryptionService({
      get: (k: string) =>
        k === 'security.tokenEncryptionKey' ? key : k === 'jwt.refreshSecret' ? refreshSecret : undefined,
    } as unknown as ConfigService);

  it('round-trips ciphertext', () => {
    const svc = build();
    const plaintext = 'sbc-access-token-value.eyJ.abc';
    const enc = svc.encrypt(plaintext);
    expect(enc).not.toContain(plaintext);
    expect(svc.decrypt(enc)).toBe(plaintext);
  });

  it('produces distinct ciphertext per call (random IV)', () => {
    const svc = build();
    expect(svc.encrypt('same')).not.toEqual(svc.encrypt('same'));
  });

  it('fails to decrypt tampered ciphertext (GCM auth)', () => {
    const svc = build();
    const enc = svc.encrypt('secret');
    const [iv, tag] = enc.split('.');
    const tampered = [iv, tag, Buffer.from('ffff', 'hex').toString('base64')].join('.');
    expect(() => svc.decrypt(tampered)).toThrow();
  });

  it('rejects a key that is not 32 bytes', () => {
    expect(
      () =>
        new EncryptionService({
          get: (k: string) => (k === 'security.tokenEncryptionKey' ? 'abcd' : refreshSecret),
        } as unknown as ConfigService),
    ).toThrow(/32 bytes/);
  });

  it('hmac is deterministic and keyed', () => {
    const svc = build();
    const token = svc.randomToken();
    expect(svc.hmac(token)).toBe(svc.hmac(token));
    expect(svc.hmac(token)).not.toBe(token);
  });
});

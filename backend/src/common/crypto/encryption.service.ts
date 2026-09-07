import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
} from 'crypto';

/**
 * AES-256-GCM encryption for secrets at rest (SBC tokens), plus HMAC helpers
 * for refresh-token fingerprints. Key is TOKEN_ENCRYPTION_KEY (32-byte hex).
 *
 * Ciphertext format: base64(iv).base64(authTag).base64(ciphertext)
 */
@Injectable()
export class EncryptionService {
  private readonly key: Buffer;
  private readonly refreshSecret: string;
  private static readonly ALGO = 'aes-256-gcm';
  private static readonly IV_LEN = 12; // 96-bit nonce, recommended for GCM

  constructor(config: ConfigService) {
    const hexKey = config.get<string>('security.tokenEncryptionKey')!;
    this.key = Buffer.from(hexKey, 'hex');
    if (this.key.length !== 32) {
      throw new Error('TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes');
    }
    this.refreshSecret = config.get<string>('jwt.refreshSecret')!;
  }

  encrypt(plaintext: string): string {
    const iv = randomBytes(EncryptionService.IV_LEN);
    const cipher = createCipheriv(EncryptionService.ALGO, this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const authTag = cipher.getAuthTag();
    return [iv.toString('base64'), authTag.toString('base64'), ciphertext.toString('base64')].join(
      '.',
    );
  }

  decrypt(payload: string): string {
    const [ivB64, tagB64, dataB64] = payload.split('.');
    if (!ivB64 || !tagB64 || !dataB64) {
      throw new Error('Malformed ciphertext');
    }
    const decipher = createDecipheriv(
      EncryptionService.ALGO,
      this.key,
      Buffer.from(ivB64, 'base64'),
    );
    decipher.setAuthTag(Buffer.from(tagB64, 'base64'));
    return Buffer.concat([
      decipher.update(Buffer.from(dataB64, 'base64')),
      decipher.final(),
    ]).toString('utf8');
  }

  /** Opaque, high-entropy token (returned to client, never stored raw). */
  randomToken(bytes = 48): string {
    return randomBytes(bytes).toString('base64url');
  }

  /** Deterministic fingerprint stored in DB — HMAC so a DB leak can't forge tokens. */
  hmac(value: string): string {
    return createHmac('sha256', this.refreshSecret).update(value).digest('hex');
  }
}

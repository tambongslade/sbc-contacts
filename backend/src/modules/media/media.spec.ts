import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { configureMediaSigning, mediaPath, verifyMediaLink } from './media-url';
import { MediaService } from './media.service';
import { sniff } from './sniff';

const JPEG = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1,
]);
const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypmp42'), Buffer.alloc(4)]);
const MOV = Buffer.concat([Buffer.from([0, 0, 0, 0x14]), Buffer.from('ftypqt  '), Buffer.alloc(4)]);
const PDF = Buffer.from('%PDF-1.7\n%âãÏÓ\n');

describe('sniff', () => {
  it('knows photos, videos and PDFs by their bytes', () => {
    expect(sniff(JPEG)?.mimeType).toBe('image/jpeg');
    expect(sniff(MP4)).toEqual({ kind: 'VIDEO', mimeType: 'video/mp4', ext: 'mp4' });
    expect(sniff(MOV)?.mimeType).toBe('video/quicktime');
    expect(sniff(PDF)?.kind).toBe('FILE');
  });

  it('turns away anything else, whatever it is called', () => {
    expect(sniff(Buffer.from('<html><script>alert(1)</script>'))).toBeNull();
    expect(sniff(Buffer.from('PK\u0003\u0004 zip file....'))).toBeNull();
  });
});

describe('signed media links', () => {
  beforeAll(() => configureMediaSigning('test-secret'));
  const id = '6f1c9b0e-1111-4222-8333-444455556666';
  const parse = (path: string) => {
    const u = new URL(path, 'https://x');
    return { exp: Number(u.searchParams.get('exp')), sig: u.searchParams.get('sig')! };
  };

  it('accepts its own link and keeps it the same all week', () => {
    const now = Date.UTC(2026, 10, 24, 10);
    const { exp, sig } = parse(mediaPath(id, now));
    expect(verifyMediaLink(id, exp, sig, now)).toBe(true);
    expect(mediaPath(id, now + 3600_000)).toBe(mediaPath(id, now));
    expect(exp * 1000 - now).toBeGreaterThan(7 * 24 * 3600_000 - 1);
  });

  it('refuses another id, a changed expiry and an expired link', () => {
    const now = Date.UTC(2026, 10, 24, 10);
    const { exp, sig } = parse(mediaPath(id, now));
    expect(verifyMediaLink('6f1c9b0e-1111-4222-8333-000000000000', exp, sig, now)).toBe(false);
    expect(verifyMediaLink(id, exp + 1, sig, now)).toBe(false);
    expect(verifyMediaLink(id, exp, sig, exp * 1000 + 1)).toBe(false);
  });
});

describe('MediaService', () => {
  let root: string;
  let prisma: Record<string, Record<string, jest.Mock>>;
  let service: MediaService;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), 'media-'));
    prisma = {
      attachment: {
        count: jest.fn().mockResolvedValue(0),
        create: jest.fn(({ data }) => Promise.resolve({ ...data, createdAt: new Date() })),
        findUnique: jest.fn(),
        updateMany: jest.fn(),
      },
    };
    const config = {
      get: (k: string) => (k === 'MEDIA_DIR' ? root : undefined),
      getOrThrow: () => 'secret',
    };
    service = new MediaService(prisma as never, { record: jest.fn() } as never, config as never);
    await service.onModuleInit();
  });
  afterEach(async () => {
    service.onModuleDestroy();
    await rm(root, { recursive: true, force: true });
  });

  async function temp(
    bytes: Buffer,
  ): Promise<{ path: string; size: number; originalname: string }> {
    const path = join(service.tempDir, `up-${Math.random()}`);
    await writeFile(path, bytes);
    return { path, size: bytes.length, originalname: 'devis.pdf' };
  }

  it('keeps a PDF on disk and returns a signed link', async () => {
    const file = await temp(PDF);
    const view = await service.upload('u1', file, {});
    expect(view).toEqual(
      expect.objectContaining({ kind: 'FILE', mimeType: 'application/pdf', fileName: 'devis.pdf' }),
    );
    expect(view.url).toMatch(new RegExp(`^/api/v1/media/${view.id}\\?exp=\\d+&sig=`));
    const key = prisma.attachment.create.mock.calls[0][0].data.storageKey as string;
    expect(await readFile(join(root, key))).toEqual(PDF);
    await expect(stat(file.path)).rejects.toThrow();
  });

  it('refuses a file that is not a photo, video or PDF, and deletes it', async () => {
    const file = await temp(Buffer.from('MZ\u0090\u0000 not an image at all'));
    await expect(service.upload('u1', file, {})).rejects.toBeInstanceOf(BadRequestException);
    await expect(stat(file.path)).rejects.toThrow();
    expect(prisma.attachment.create).not.toHaveBeenCalled();
  });

  it('refuses a photo over 10 Mo', async () => {
    const file = await temp(JPEG);
    await expect(service.upload('u1', { ...file, size: 11 * 1024 * 1024 }, {})).rejects.toThrow(
      '10 Mo',
    );
  });

  it('only claims the uploader’s own unsent attachments', async () => {
    const tx = { attachment: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) } };
    await expect(
      service.claim(tx as never, 'u1', ['a', 'b'], { messageId: 'm1' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.attachment.updateMany).toHaveBeenCalledWith({
      where: {
        id: { in: ['a', 'b'] },
        uploaderId: 'u1',
        requestId: null,
        dispatchId: null,
        messageId: null,
      },
      data: { messageId: 'm1' },
    });
    await expect(
      service.claim(tx as never, 'u1', ['a', 'b', 'c', 'd', 'e', 'f'], { messageId: 'm1' }),
    ).rejects.toThrow('5 pièces jointes maximum');
  });

  it('serves nothing for a forged link', async () => {
    await expect(service.resolveLink('a', 9_999_999_999, 'forged')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

import { ConflictException, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';

/**
 * SBC Network accounts live in SBC Network only: no SBC account behind them,
 * signed in with their WhatsApp number.
 */
describe('AuthService — SBC Network accounts', () => {
  const meta = { ip: '127.0.0.1' };

  function build() {
    const tx = {
      user: { create: jest.fn(async ({ data }) => ({ id: 'u1', role: 'USER', ...data })) },
      member: { create: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      user: { findFirst: jest.fn().mockResolvedValue(null), update: jest.fn() },
      $transaction: jest.fn(async (fn: (t: typeof tx) => unknown) => fn(tx)),
    };
    const tokens = { issueForUser: jest.fn().mockResolvedValue({ accessToken: 'a' }) };
    const service = new AuthService(prisma as never, {} as never, {} as never, tokens as never);
    return { service, prisma, tx, tokens };
  }

  const dto = { name: 'Jean', country: 'CM', phoneNumber: '670 00 00 00', password: 'secret123' };

  it('creates the account in SBC Network, with its member profile, and signs it in', async () => {
    const { service, tx, tokens } = build();

    const result = await service.register(dto, meta);

    const data = tx.user.create.mock.calls[0][0].data;
    expect(data).toEqual(
      expect.objectContaining({ origin: 'NETWORK', phoneNumber: '237670000000', country: 'CM' }),
    );
    expect(data.sbcUserId).toMatch(/^net_/);
    expect(await bcrypt.compare('secret123', data.passwordHash)).toBe(true);
    expect(tx.member.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ sbcId: data.sbcUserId, source: 'NETWORK' }),
    });
    expect(tokens.issueForUser).toHaveBeenCalled();
    expect(result.user.origin).toBe('NETWORK');
    expect(result.user).not.toHaveProperty('passwordHash');
  });

  it('refuses a second account on the same number', async () => {
    const { service, prisma } = build();
    prisma.user.findFirst.mockResolvedValue({ id: 'u0' });

    await expect(service.register(dto, meta)).rejects.toBeInstanceOf(ConflictException);
  });

  it('signs in with the number however it is typed', async () => {
    const { service, prisma } = build();
    const passwordHash = await bcrypt.hash('secret123', 4);
    prisma.user.findFirst.mockResolvedValue({
      id: 'u1',
      sbcUserId: 'net_1',
      role: 'USER',
      origin: 'NETWORK',
      passwordHash,
    });

    const result = await service.loginWithPhone(
      { phoneNumber: '+237 670 00 00 00', password: 'secret123' },
      meta,
    );

    expect(prisma.user.findFirst.mock.calls[0][0].where).toEqual(
      expect.objectContaining({ origin: 'NETWORK', phoneNumber: '237670000000' }),
    );
    expect(result.user.id).toBe('u1');
  });

  it('gives one generic error for a wrong password or an unknown number', async () => {
    const { service, prisma } = build();
    const passwordHash = await bcrypt.hash('secret123', 4);
    prisma.user.findFirst.mockResolvedValueOnce({ id: 'u1', passwordHash });

    await expect(
      service.loginWithPhone({ phoneNumber: '237670000000', password: 'nope' }, meta),
    ).rejects.toThrow(new UnauthorizedException('Numéro ou mot de passe incorrect'));
    await expect(
      service.loginWithPhone({ phoneNumber: '237699999999', password: 'secret123' }, meta),
    ).rejects.toThrow(new UnauthorizedException('Numéro ou mot de passe incorrect'));
  });
});

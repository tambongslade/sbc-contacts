import { ForbiddenException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SbcClientService } from './sbc-client.service';

function mockFetch(status: number, body: unknown, contentType = 'application/json') {
  return jest.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => (typeof body === 'string' ? body : JSON.stringify(body)),
    headers: { get: () => contentType },
  } as unknown as Response);
}

describe('SbcClientService', () => {
  const config = {
    get: (k: string) =>
      ({
        'sbc.baseUrl': 'https://sbc.test',
        'sbc.clientId': 'sbc-contacts',
        'sbc.clientSecret': 'secret',
        'sbc.redirectUri': 'https://app/cb',
      })[k],
  } as unknown as ConfigService;

  afterEach(() => jest.restoreAllMocks());

  it('normalises fr/en aliased contacts and paging', async () => {
    global.fetch = mockFetch(200, {
      success: true,
      data: {
        contacts: [
          {
            _id: 'm1',
            nom: 'Doe',
            prenom: 'Jane',
            ville: 'Douala',
            pays: 'CM',
            metier: 'Designer',
            sexe: 'F',
            age: 30,
            competences: ['figma'],
            centresInteret: ['business'],
            photo: 'https://img/1',
            telephone: '237690',
          },
        ],
        total: 1,
        page: 1,
        limit: 20,
      },
    });

    const svc = new SbcClientService(config);
    const res = await svc.searchContacts('token', { country: 'CM' });

    expect(res.total).toBe(1);
    expect(res.items[0]).toMatchObject({
      id: 'm1',
      name: 'Doe',
      firstName: 'Jane',
      city: 'Douala',
      country: 'CM',
      profession: 'Designer',
      sex: 'F',
      age: 30,
      skills: ['figma'],
      interests: ['business'],
      avatarUrl: 'https://img/1',
      phoneNumber: '237690',
    });
  });

  it('propagates SBC 403 code (SUBSCRIPTION_REQUIRED)', async () => {
    global.fetch = mockFetch(403, {
      success: false,
      code: 'SUBSCRIPTION_REQUIRED',
      message: 'No active subscription',
    });

    const svc = new SbcClientService(config);
    try {
      await svc.searchContacts('token', {});
      fail('should have thrown');
    } catch (e) {
      expect(e).toBeInstanceOf(ForbiddenException);
      expect((e as ForbiddenException).getResponse()).toMatchObject({
        code: 'SUBSCRIPTION_REQUIRED',
      });
    }
  });

  it('builds a query string from filters', async () => {
    const fetchMock = mockFetch(200, { success: true, data: { items: [], total: 0 } });
    global.fetch = fetchMock;
    const svc = new SbcClientService(config);
    await svc.searchContacts('token', { country: 'CM', profession: 'Maçon', interests: ['a', 'b'] });
    const calledUrl = fetchMock.mock.calls[0][0] as string;
    expect(calledUrl).toContain('/api/contacts/sso/search?');
    expect(calledUrl).toContain('country=CM');
    expect(calledUrl).toContain('interests=a');
    expect(calledUrl).toContain('interests=b');
  });
});

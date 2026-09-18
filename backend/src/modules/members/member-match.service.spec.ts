import { PrismaService } from '../../infrastructure/prisma/prisma.service';
import { MemberMatchService } from './member-match.service';
import { MatchCriteria } from './member.view';

describe('MemberMatchService.buildWhere', () => {
  const svc = new MemberMatchService({} as unknown as PrismaService);
  const base: MatchCriteria = {
    countries: [],
    cities: [],
    professions: [],
    interests: [],
  };

  it('empty criteria → empty where (matches everything)', () => {
    expect(svc.buildWhere(base)).toEqual({});
  });

  it('maps multi-value arrays to IN / hasSome', () => {
    const where = svc.buildWhere({
      ...base,
      countries: ['CM', 'FR'],
      cities: ['Douala'],
      professions: ['Designer', 'Maçon'],
      interests: ['business', 'tech'],
    });
    expect(where).toMatchObject({ interests: { hasSome: ['business', 'tech'] } });
    // Country, région and profession are all compared case-insensitively — SBC
    // stores them as typed, so an exact IN dropped every row spelled
    // differently. Each field is its own OR group, and the groups are ANDed.
    const groups = where.AND as Array<{ OR: Array<Record<string, unknown>> }>;
    expect(groups).toHaveLength(3);
    expect(groups[1].OR).toEqual([{ city: { equals: 'Douala', mode: 'insensitive' } }]);
    expect(groups[2].OR).toEqual([
      { profession: { equals: 'Designer', mode: 'insensitive' } },
      { profession: { equals: 'Maçon', mode: 'insensitive' } },
    ]);
    // Country still expands through the alias table — a criteria asks for "CM"
    // and the mirror may hold the display name, which case folding alone never
    // turns into the code.
    const countries = groups[0].OR.map((clause) => {
      const field = clause.country as { equals: string; mode: string };
      expect(field.mode).toBe('insensitive');
      return field.equals;
    });
    expect(countries).toEqual(expect.arrayContaining(['cm', 'fr', 'cameroun']));
  });

  it('matches a country the mirror shouted in capitals', () => {
    // The real shape of the bug: SBC hands back "CAMEROUN", the alias table
    // lists "Cameroun", and an exact IN counted 2 members out of hundreds.
    const member = { country: 'CAMEROUN' } as Parameters<typeof svc.matchesMember>[0];
    expect(svc.matchesMember(member, { ...base, countries: ['CM'] })).toBe(true);
    expect(svc.matchesMember(member, { ...base, countries: ['SN'] })).toBe(false);
  });

  it('matches a région the mirror holds in another casing', () => {
    const member = { city: 'LITTORAL  ' } as Parameters<typeof svc.matchesMember>[0];
    expect(svc.matchesMember(member, { ...base, cities: ['Littoral'] })).toBe(true);
    expect(svc.matchesMember(member, { ...base, cities: ['Centre'] })).toBe(false);
  });

  it('matches a member whose country was mirrored as a display name', () => {
    const member = { country: 'Cameroun' } as Parameters<typeof svc.matchesMember>[0];
    expect(svc.matchesMember(member, { ...base, countries: ['CM'] })).toBe(true);
    expect(svc.matchesMember(member, { ...base, countries: ['FR'] })).toBe(false);
  });

  it('maps sex and an age range', () => {
    const where = svc.buildWhere({ ...base, sex: 'F', ageMin: 25, ageMax: 40 });
    expect(where).toMatchObject({ sex: 'F', age: { gte: 25, lte: 40 } });
  });

  it('supports an open-ended age (min only)', () => {
    expect(svc.buildWhere({ ...base, ageMin: 18 })).toMatchObject({ age: { gte: 18 } });
    expect(svc.buildWhere({ ...base, ageMax: 65 })).toMatchObject({ age: { lte: 65 } });
  });

  it('ignores empty arrays and nullish scalars', () => {
    const where = svc.buildWhere({ ...base, sex: null, ageMin: null, ageMax: null });
    expect(where).toEqual({});
  });
});

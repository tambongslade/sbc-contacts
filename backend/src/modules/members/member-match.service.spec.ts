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
    expect(where).toMatchObject({
      country: { in: ['CM', 'FR'] },
      city: { in: ['Douala'] },
      profession: { in: ['Designer', 'Maçon'] },
      interests: { hasSome: ['business', 'tech'] },
    });
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

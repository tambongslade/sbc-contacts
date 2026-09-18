import { aggregateRegions } from './regions';

describe('aggregateRegions', () => {
  it('normalises countries to ISO codes and merges spellings of one région', () => {
    const result = aggregateRegions([
      { country: 'CM', city: 'Littoral', count: 30 },
      { country: 'Cameroun', city: 'littoral ', count: 5 },
      { country: 'cameroon', city: 'LITTORAL', count: 2 },
      { country: 'CM', city: 'Centre', count: 10 },
    ]);
    expect(result).toEqual([
      { country: 'CM', region: 'Littoral', count: 37 },
      { country: 'CM', region: 'Centre', count: 10 },
    ]);
  });

  it('keeps the most frequent spelling', () => {
    const [entry] = aggregateRegions([
      { country: 'CI', city: 'abidjan', count: 3 },
      { country: 'CI', city: 'Abidjan', count: 9 },
    ]);
    expect(entry).toEqual({ country: 'CI', region: 'Abidjan', count: 12 });
  });

  it('keeps the same name apart across countries', () => {
    const result = aggregateRegions([
      { country: 'CM', city: 'Centre', count: 4 },
      { country: 'BF', city: 'Centre', count: 6 },
    ]);
    expect(result).toEqual([
      { country: 'BF', region: 'Centre', count: 6 },
      { country: 'CM', region: 'Centre', count: 4 },
    ]);
  });

  it('drops rows without a usable country or région', () => {
    expect(
      aggregateRegions([
        { country: null, city: 'Dakar', count: 3 },
        { country: 'SN', city: null, count: 3 },
        { country: 'SN', city: '   ', count: 3 },
        { country: 'Atlantide', city: 'Nulle part', count: 3 },
        { country: 'FR', city: 'Île-de-France', count: 2 },
      ]),
    ).toEqual([{ country: 'FR', region: 'Île-de-France', count: 2 }]);
  });
});

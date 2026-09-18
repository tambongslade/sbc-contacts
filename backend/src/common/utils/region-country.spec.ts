import { countryForRegion, regionsForCountry, unambiguousRegions } from './region-country';

/**
 * SBC's search sends no country, so the région is the only thing a country can
 * be derived from — and getting that derivation wrong puts the wrong people in
 * somebody's phone book.
 */
describe('region → country', () => {
  it('resolves a région that belongs to one country', () => {
    expect(countryForRegion('Extrême-Nord')).toBe('CM');
    expect(countryForRegion('Abidjan')).toBe('CI');
    expect(countryForRegion('Dakar')).toBe('SN');
  });

  it('refuses to guess a région two countries share', () => {
    // "Centre" is Cameroon and Burkina Faso, "Littoral" Cameroon and Benin.
    // Writing CM on either would put Burkinabè and Béninois members into
    // Cameroonian criteria — silently, and onto a real phone.
    expect(countryForRegion('Centre')).toBeUndefined();
    expect(countryForRegion('Littoral')).toBeUndefined();
    expect(countryForRegion('Savanes')).toBeUndefined();
  });

  it('reads a région however SBC typed it', () => {
    expect(countryForRegion('  ABIDJAN ')).toBe('CI');
    expect(countryForRegion('extreme-nord')).toBe('CM');
    expect(countryForRegion('Extreme Nord')).toBe('CM');
  });

  it('resolves the cities SBC sends in the région field, not just admin régions', () => {
    // The largest group of Cameroonian members arrive as a city, not "Centre".
    expect(countryForRegion('Yaoundé')).toBe('CM');
    expect(countryForRegion('yaounde')).toBe('CM'); // accent- and case-folded
    expect(countryForRegion('Douala')).toBe('CM');
    expect(countryForRegion('Bafoussam')).toBe('CM');
    expect(countryForRegion('Cotonou')).toBe('BJ');
    expect(countryForRegion('Ouagadougou')).toBe('BF');
    // A city and a région of the same country both widen it.
    expect(regionsForCountry('CM')).toEqual(expect.arrayContaining(['Yaoundé', 'Douala', 'Littoral']));
  });

  it('is undefined for anything it has never seen', () => {
    expect(countryForRegion('Wouri')).toBeUndefined();
    expect(countryForRegion('')).toBeUndefined();
    expect(countryForRegion(null)).toBeUndefined();
  });

  it('lists every région of a country, shared ones included', () => {
    const cm = regionsForCountry('CM');
    // The widening is the whole point: these two are where most Cameroonian
    // members live, and neither can be derived on ingest.
    expect(cm).toEqual(expect.arrayContaining(['Littoral', 'Centre', 'Ouest', 'Extrême-Nord']));
    expect(regionsForCountry('cm')).toEqual(cm);
    expect(regionsForCountry(null)).toEqual([]);
  });

  it('offers the backfill only the régions it can be sure of', () => {
    const rows = unambiguousRegions();
    expect(rows.every((r) => countryForRegion(r.region) === r.country)).toBe(true);
    expect(rows.map((r) => r.region)).not.toContain('Centre');
    expect(rows.map((r) => r.region)).not.toContain('Littoral');
  });
});

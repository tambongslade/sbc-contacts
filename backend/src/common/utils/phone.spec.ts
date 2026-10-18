import { toInternationalPhone } from './phone';

describe('toInternationalPhone', () => {
  it('prefixes the country code to a local number', () => {
    expect(toInternationalPhone('6 70 00 00 00', 'CM')).toBe('237670000000');
  });

  it('keeps a number typed with its country code', () => {
    expect(toInternationalPhone('+237 670 00 00 00', 'CI')).toBe('237670000000');
    expect(toInternationalPhone('00237670000000')).toBe('237670000000');
    expect(toInternationalPhone('237670000000', 'CM')).toBe('237670000000');
  });

  it('drops the trunk 0 of a national number', () => {
    expect(toInternationalPhone('06 12 34 56 78', 'FR')).toBe('33612345678');
  });

  it('refuses what cannot be a phone number', () => {
    expect(toInternationalPhone('12', 'CM')).toBeNull();
    expect(toInternationalPhone('abc')).toBeNull();
  });
});

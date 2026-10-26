import { approximateKm, distanceKm, toLatLng } from './geo';

describe('geo', () => {
  it('measures Douala to Yaoundé at about 200 km', () => {
    const douala = { latitude: 4.0511, longitude: 9.7679 };
    const yaounde = { latitude: 3.848, longitude: 11.5021 };
    expect(distanceKm(douala, yaounde)).toBeGreaterThan(190);
    expect(distanceKm(douala, yaounde)).toBeLessThan(200);
  });

  it('is zero for the same point', () => {
    const p = { latitude: 4.05, longitude: 9.76 };
    expect(distanceKm(p, p)).toBe(0);
  });

  it('rounds to half-km steps up close and whole km further out', () => {
    expect(approximateKm(0.1)).toBe(0.5);
    expect(approximateKm(1.3)).toBe(1.5);
    expect(approximateKm(4.7)).toBe(4.5);
    expect(approximateKm(12.4)).toBe(12);
  });

  it('needs both coordinates', () => {
    expect(toLatLng({ latitude: 4, longitude: null })).toBeNull();
    expect(toLatLng({ latitude: 0, longitude: 0 })).toEqual({ latitude: 0, longitude: 0 });
  });
});

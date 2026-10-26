/** A position as the phone reports it. */
export interface LatLng {
  latitude: number;
  longitude: number;
}

const EARTH_RADIUS_KM = 6371;

/** Great-circle distance in km (haversine) — plenty at city scale. */
export function distanceKm(a: LatLng, b: LatLng): number {
  const rad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLng = rad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * A distance as it may be shown to the other side: coarse enough that it does
 * not give away where someone stands. Half-km steps up to 5 km (never below
 * 0.5), whole km beyond.
 */
export function approximateKm(km: number): number {
  if (km < 5) return Math.max(0.5, Math.round(km * 2) / 2);
  return Math.round(km);
}

/** Both coordinates present, as a [LatLng]; null otherwise. */
export function toLatLng(p: { latitude: number | null; longitude: number | null }): LatLng | null {
  return p.latitude != null && p.longitude != null
    ? { latitude: p.latitude, longitude: p.longitude }
    : null;
}

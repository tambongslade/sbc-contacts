/**
 * Single source of truth for the "score de confiance" formula.
 *
 * Everyone starts at 50/100. The score is an average-based mapping of the mean
 * star rating onto 0-100, with 3★ as the neutral midpoint:
 *   1★ → 0, 3★ → 50, 5★ → 100.
 * With no reviews the score is the neutral baseline of 50. Being average-based
 * (not a running delta) it can't be inflated by review volume.
 */
export function confidenceScore(averageStars: number, reviewCount: number): number {
  if (reviewCount <= 0) return 50;
  const raw = ((averageStars - 1) / 4) * 100;
  return Math.max(0, Math.min(100, Math.round(raw)));
}

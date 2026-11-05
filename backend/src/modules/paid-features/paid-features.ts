import { SbcSubscription } from '../sbc-client/interfaces/sbc.interface';

/**
 * The app's paid features and the SBC subscription types that pay for them.
 * SBC sells them (docs/paiements-sbc.md); the app only reads what was paid.
 *
 *  - PRO: receiving client requests ("Espace pro"), 2 000 FCFA/mois.
 *    Paid until → ProProfile.receivingUntil (receivingEnabled = true).
 *  - SPOTLIGHT: "Mise en avant", 3 000 FCFA/mois.
 *    Paid until → User.spotlightUntil.
 *
 * CLASSIQUE and CIBLE (the SBC membership) stay as they are: read from
 * User.subscriptionTypes wherever the directory needs them.
 */
export type PaidFeature = 'PRO' | 'SPOTLIGHT';

export const PAID_FEATURE_TYPES: Record<PaidFeature, string[]> = {
  PRO: ['PRO'],
  SPOTLIGHT: ['MISE_EN_AVANT', 'SPOTLIGHT'],
};

/**
 * A paid type SBC reports without an end date keeps the feature on this long.
 * Every app open and every SBC webhook pushes it forward again, so it only
 * matters once SBC stops listing the type: the feature then ends within it.
 */
export const UNDATED_GRACE_DAYS = 3;

/** The SBC side of a member, as the session and the webhooks carry it. */
export interface SbcPaidState {
  subscriptionTypes?: string[] | null;
  subscriptions?: SbcSubscription[] | null;
}

function isType(type: string, feature: PaidFeature): boolean {
  return PAID_FEATURE_TYPES[feature].includes(type.trim().toUpperCase());
}

/**
 * Until when SBC says [feature] is paid, or null when it is not paid.
 * Dated subscriptions win; otherwise the type's presence in
 * `subscriptionTypes` counts, for [UNDATED_GRACE_DAYS].
 */
export function paidUntil(sbc: SbcPaidState, feature: PaidFeature, now = new Date()): Date | null {
  const grace = new Date(now.getTime() + UNDATED_GRACE_DAYS * 24 * 60 * 60 * 1000);
  const dated = (sbc.subscriptions ?? []).filter((s) => isType(s.type ?? '', feature));
  if (dated.length) {
    let best: Date | null = null;
    for (const s of dated) {
      if ((s.status ?? 'active').toLowerCase() !== 'active') continue;
      const end = s.expiresAt ? new Date(s.expiresAt) : grace;
      if (Number.isNaN(end.getTime()) || end <= now) continue;
      if (!best || end > best) best = end;
    }
    return best;
  }
  return (sbc.subscriptionTypes ?? []).some((t) => isType(t, feature)) ? grace : null;
}

/**
 * The later of two "paid until" dates, where null means "no end" (a free
 * iOS reception, an admin grant without date) and must never be shortened.
 */
export function extendUntil(
  current: Date | null | undefined,
  paid: Date,
  keepOpenEnded: boolean,
): Date | null {
  if (keepOpenEnded) return null;
  return current && current > paid ? current : paid;
}

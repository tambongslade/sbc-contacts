/**
 * Text helpers shared by SBC Data matching. Requests and services are typed by
 * people ("Réparation de Locks", "reparer mes locks"), so every comparison runs
 * on a folded form: lower case, no accents, no punctuation.
 */

/** Words that carry no meaning for matching a need to a service. */
// prettier-ignore
const STOPWORDS = new Set([
  'les', 'des', 'une', 'pour', 'avec', 'sans', 'dans', 'sur', 'par', 'mes', 'mon', 'mais',
  'est', 'suis', 'qui', 'que', 'quoi', 'quelqu', 'quelque', 'chose', 'cherche', 'besoin',
  'veux', 'voudrais', 'aimerais', 'faire', 'fait', 'fais', 'aux', 'ses', 'son', 'leur',
  'nos', 'vos', 'votre', 'notre', 'tres', 'plus', 'tout', 'tous', 'the', 'and', 'for',
]);

export function fold(input: string | null | undefined): string {
  return (input ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Meaningful tokens, with a crude French plural/verb fold ("locks" → "lock",
 * "réparer"/"réparation" → "repar") so a need and a service phrased differently
 * still meet.
 */
export function tokens(...inputs: Array<string | null | undefined>): Set<string> {
  const out = new Set<string>();
  for (const input of inputs) {
    for (const word of fold(input).split(' ')) {
      if (word.length < 3 || STOPWORDS.has(word)) continue;
      out.add(stem(word));
    }
  }
  return out;
}

function stem(word: string): string {
  // Feminine professions meet their masculine form ("coiffeuse" = "coiffeur").
  if (word.endsWith('euses') || word.endsWith('euse')) word = word.replace(/euses?$/, 'eur');
  else if (word.endsWith('iennes') || word.endsWith('ienne'))
    word = word.replace(/iennes?$/, 'ien');
  for (const suffix of ['ations', 'ation', 'ateur', 'atrice', 'ement', 'er', 'es', 's']) {
    if (word.length - suffix.length >= 4 && word.endsWith(suffix)) {
      return word.slice(0, -suffix.length);
    }
  }
  return word;
}

/** Share of [need] tokens found in [offer]; 0 when the need is empty. */
export function coverage(need: Set<string>, offer: Set<string>): number {
  if (need.size === 0) return 0;
  let hit = 0;
  for (const t of need) if (offer.has(t)) hit++;
  return hit / need.size;
}

export function cosine(a: number[], b: number[]): number {
  if (a.length === 0 || a.length !== b.length) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na && nb ? dot / Math.sqrt(na * nb) : 0;
}

/** Same place, however it was typed ("Yaoundé" = "yaounde"). */
export function samePlace(a: string | null | undefined, b: string | null | undefined): boolean {
  const fa = fold(a);
  return fa.length > 0 && fa === fold(b);
}

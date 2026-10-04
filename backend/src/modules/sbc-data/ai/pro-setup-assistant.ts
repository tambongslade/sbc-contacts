import { Injectable, Logger } from '@nestjs/common';
import { ServiceMode } from '@prisma/client';
import { isPlaceholder } from '../text';
import { GeminiClient, GeminiUnavailableError } from './gemini.client';

/** The profile being built, as far as the conversation got. */
export interface ProDraft {
  profile: {
    profession: string | null;
    description: string | null;
    city: string | null;
    zones: string[];
    modes: ServiceMode[];
    availability: string | null;
    priceMin: number | null;
    priceMax: number | null;
    shopUrl: string | null;
  };
  services: Array<{
    name: string;
    category: string;
    profession: string;
    synonyms: string[];
    specialties: string[];
  }>;
}

export type DraftField =
  'profession' | 'description' | 'city' | 'modes' | 'availability' | 'shopUrl' | 'services';

export interface AssistantTurn {
  /** The assistant's next message: one short question, or the wrap-up. */
  reply: string;
  /** Tappable answers for that question, when it has obvious ones. */
  options: string[];
  draft: ProDraft;
  /** What is still needed — computed here, never taken from the model. */
  missing: DraftField[];
  complete: boolean;
  /** False when Gemini could not answer; the app then offers the form. */
  available: boolean;
}

export interface AssistantContext {
  name: string | null;
  country: string | null;
  /** Services the pro already has, so the assistant does not repeat them. */
  existingServices: string[];
}

const MODES = Object.values(ServiceMode);

const SCHEMA = {
  type: 'OBJECT',
  properties: {
    reply: { type: 'STRING' },
    options: { type: 'ARRAY', items: { type: 'STRING' } },
    profile: {
      type: 'OBJECT',
      properties: {
        profession: { type: 'STRING', nullable: true },
        description: { type: 'STRING', nullable: true },
        city: { type: 'STRING', nullable: true },
        zones: { type: 'ARRAY', items: { type: 'STRING' } },
        modes: { type: 'ARRAY', items: { type: 'STRING', enum: MODES } },
        availability: { type: 'STRING', nullable: true },
        priceMin: { type: 'INTEGER', nullable: true },
        priceMax: { type: 'INTEGER', nullable: true },
        shopUrl: { type: 'STRING', nullable: true },
      },
      required: [
        'profession',
        'description',
        'city',
        'zones',
        'modes',
        'availability',
        'priceMin',
        'priceMax',
        'shopUrl',
      ],
    },
    services: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          category: { type: 'STRING' },
          synonyms: { type: 'ARRAY', items: { type: 'STRING' } },
          specialties: { type: 'ARRAY', items: { type: 'STRING' } },
        },
        required: ['name', 'category', 'synonyms', 'specialties'],
      },
    },
  },
  required: ['reply', 'options', 'profile', 'services'],
};

const SYSTEM = `Tu es l'assistant de SBC Network qui aide un membre à créer son profil professionnel, pour qu'il reçoive les demandes des clients qui ont besoin de ses services. Le marché est l'Afrique francophone (Cameroun, Côte d'Ivoire, Togo…), les prix sont en FCFA.

Règles :
- Pose UNE seule question courte à la fois, en français simple, en tutoyant. Pas de jargon.
- Ne devine jamais si la personne est un homme ou une femme : formule sans accord (« Où travailles-tu ? », pas « Où es-tu basé ? »).
- Mets à jour le brouillon avec ce que la personne a dit. N'invente jamais une information qu'elle n'a pas donnée.
- Ne repose pas une question dont la réponse est déjà dans le brouillon.
- Ordre : 1) ce qu'elle propose (métier et prestations) ; 2) sa ville principale, puis les autres quartiers ou villes où elle intervient ; 3) comment elle travaille : à domicile (HOME), sur place chez elle (ON_SITE), en ligne (ONLINE), livraison (DELIVERY) ; 4) ses disponibilités ; 5) une fourchette de prix, facultative ("je ne sais pas" est accepté) ; 6) le lien de sa boutique SBC Shop, obligatoire : c'est là que les clients voient ses photos et réalisations.
- profession : le métier au masculin singulier ("Coiffeur", "Plombier").
- description : rédige-la toi-même, 2 à 3 phrases à la première personne, à partir de ses réponses.
- services : un élément par prestation distincte qu'un client pourrait demander, nommée clairement ("Réparation de locks"), avec les synonymes qu'un client utiliserait (argot, variantes locales) et les spécialités mentionnées. Ne répète pas les services qu'elle a déjà.
- options : 2 à 4 réponses rapides quand la question en a d'évidentes (ex. pour le mode de travail), sinon [].
- Quand tout est rempli, dis-lui de vérifier son profil ci-dessous, sans poser de nouvelle question.`;

/**
 * Builds a pro profile and services through a short conversation, instead of
 * a form (the pro "explains", the AI fills in). Stateless: the app sends the
 * transcript and the draft back each turn, so nothing is half-saved.
 */
@Injectable()
export class ProSetupAssistant {
  private readonly logger = new Logger(ProSetupAssistant.name);

  constructor(private readonly gemini: GeminiClient) {}

  async turn(
    context: AssistantContext,
    messages: Array<{ role: 'user' | 'assistant'; text: string }>,
    previous: ProDraft,
  ): Promise<AssistantTurn> {
    const before = sanitise(previous);
    const known = [
      context.name && `Nom : ${context.name}`,
      context.country && `Pays : ${context.country}`,
      context.existingServices.length &&
        `Services déjà enregistrés : ${context.existingServices.join(', ')}`,
      `Brouillon actuel : ${JSON.stringify(before)}`,
      `Encore à obtenir : ${missingFields(before, context.existingServices.length > 0).join(', ') || 'rien'}`,
    ]
      .filter(Boolean)
      .join('\n');

    // Gemini wants the conversation to open on a user turn.
    const turns: Array<{ role: 'user' | 'model'; text: string }> = [
      { role: 'user', text: '(Le membre ouvre l’assistant.)' },
      ...messages.slice(-30).map((m) => ({
        role: m.role === 'assistant' ? ('model' as const) : ('user' as const),
        text: m.text.slice(0, 1000),
      })),
    ];
    if (turns[turns.length - 1].role === 'model') {
      turns.push({ role: 'user', text: '(Continue.)' });
    }

    try {
      const raw = await this.gemini.generateJsonChat<{
        reply: string;
        options: string[];
        profile: ProDraft['profile'];
        services: Array<Omit<ProDraft['services'][number], 'profession'>>;
      }>(`${SYSTEM}\n\n${known}`, turns, SCHEMA, 0.4);

      const draft = sanitise({
        profile: raw.profile,
        services: (raw.services ?? []).map((s) => ({
          ...s,
          profession: raw.profile?.profession ?? before.profile.profession ?? '',
        })),
      });
      const missing = missingFields(draft, context.existingServices.length > 0);
      return {
        reply: clean(raw.reply) || 'Peux-tu m’en dire un peu plus ?',
        options: missing.length ? cleanList(raw.options).slice(0, 4) : [],
        draft,
        missing,
        complete: missing.length === 0,
        available: true,
      };
    } catch (err) {
      if (!(err instanceof GeminiUnavailableError)) throw err;
      this.logger.warn(`Setup assistant unavailable: ${err.message}`);
      const missing = missingFields(before, context.existingServices.length > 0);
      return {
        reply:
          'L’assistant n’est pas disponible pour le moment. Tu peux remplir ton profil toi-même.',
        options: [],
        draft: before,
        missing,
        complete: missing.length === 0,
        available: false,
      };
    }
  }
}

/** What a profile still lacks for matching to find the pro. */
export function missingFields(draft: ProDraft, hasServices: boolean): DraftField[] {
  const p = draft.profile;
  const out: DraftField[] = [];
  if (isPlaceholder(p.profession)) out.push('profession');
  if (isPlaceholder(p.description) || (p.description ?? '').length < 10) out.push('description');
  if (isPlaceholder(p.city)) out.push('city');
  if (p.modes.length === 0) out.push('modes');
  if (isPlaceholder(p.availability)) out.push('availability');
  if (!isHttpUrl(p.shopUrl)) out.push('shopUrl');
  if (!hasServices && draft.services.length === 0) out.push('services');
  return out;
}

/** Whatever came back (from the model or the app), in the shape we trust. */
export function sanitise(draft: Partial<ProDraft> | null | undefined): ProDraft {
  const p: Partial<ProDraft['profile']> = draft?.profile ?? {};
  const text = (v: unknown) => (typeof v === 'string' && !isPlaceholder(v) ? clean(v) : null);
  const amount = (v: unknown) => (Number.isInteger(v) && (v as number) >= 0 ? (v as number) : null);
  const seen = new Set<string>();
  return {
    profile: {
      profession: text(p.profession),
      description: text(p.description),
      city: text(p.city),
      zones: cleanList(p.zones).filter((z) => !isPlaceholder(z)),
      modes: [...new Set((p.modes ?? []).filter((m): m is ServiceMode => MODES.includes(m)))],
      availability: text(p.availability),
      priceMin: amount(p.priceMin),
      priceMax: amount(p.priceMax),
      shopUrl: isHttpUrl(p.shopUrl) ? clean(p.shopUrl as string) : null,
    },
    services: (draft?.services ?? [])
      .filter((s) => clean(s?.name))
      .filter((s) => {
        const k = clean(s.name).toLowerCase();
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      })
      .slice(0, 20)
      .map((s) => ({
        name: clean(s.name).slice(0, 120),
        category: clean(s.category).slice(0, 120) || clean(s.name).slice(0, 120),
        profession: clean(s.profession).slice(0, 80),
        synonyms: cleanList(s.synonyms).slice(0, 30),
        specialties: cleanList(s.specialties).slice(0, 20),
      })),
  };
}

function isHttpUrl(v: unknown): boolean {
  if (typeof v !== 'string') return false;
  try {
    const u = new URL(v.trim());
    // example.com and friends are what people type to get past a field.
    const placeholderHost = /(^|\.)example\.(com|org|net)$/.test(u.hostname);
    return (
      (u.protocol === 'https:' || u.protocol === 'http:') &&
      u.hostname.includes('.') &&
      !placeholderHost
    );
  } catch {
    return false;
  }
}

function clean(value: unknown): string {
  return typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
}

function cleanList(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.map(clean).filter(Boolean))];
}

import { Injectable, Logger } from '@nestjs/common';
import { ServiceMode } from '@prisma/client';
import { GeminiClient, GeminiUnavailableError } from './gemini.client';

/** One service as the AI proposes it; the pro accepts, edits or drops it (Data §4). */
export interface ServiceProposal {
  name: string;
  category: string;
  profession: string;
  synonyms: string[];
  specialties: string[];
}

export interface StructuredServices {
  profession: string;
  category: string;
  services: ServiceProposal[];
}

/** The minimum structured reading of a request (Data §7). */
export interface RequestAnalysis {
  profession: string | null;
  service: string | null;
  specialties: string[];
  city: string | null;
  district: string | null;
  mode: ServiceMode | null;
  desiredDate: string | null;
  desiredTime: string | null;
  budget: number | null;
  constraints: string[];
  clarificationQuestion: string | null;
  clarificationOptions: string[];
}

/** A shortlisted service the judge is asked about. */
export interface JudgeCandidate {
  id: string;
  service: string;
  category: string;
  profession: string;
  specialties: string[];
}

const MODES = Object.values(ServiceMode);

const STRUCTURE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    profession: { type: 'STRING' },
    category: { type: 'STRING' },
    services: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          synonyms: { type: 'ARRAY', items: { type: 'STRING' } },
          specialties: { type: 'ARRAY', items: { type: 'STRING' } },
        },
        required: ['name', 'synonyms', 'specialties'],
      },
    },
  },
  required: ['profession', 'category', 'services'],
};

const ANALYSIS_SCHEMA = {
  type: 'OBJECT',
  properties: {
    profession: { type: 'STRING', nullable: true },
    service: { type: 'STRING', nullable: true },
    specialties: { type: 'ARRAY', items: { type: 'STRING' } },
    city: { type: 'STRING', nullable: true },
    district: { type: 'STRING', nullable: true },
    mode: { type: 'STRING', enum: MODES, nullable: true },
    desiredDate: { type: 'STRING', nullable: true },
    desiredTime: { type: 'STRING', nullable: true },
    budget: { type: 'INTEGER', nullable: true },
    constraints: { type: 'ARRAY', items: { type: 'STRING' } },
    clarificationQuestion: { type: 'STRING', nullable: true },
    clarificationOptions: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: [
    'profession',
    'service',
    'specialties',
    'city',
    'district',
    'mode',
    'desiredDate',
    'desiredTime',
    'budget',
    'constraints',
    'clarificationQuestion',
    'clarificationOptions',
  ],
};

const JUDGE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    verdicts: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          id: { type: 'STRING' },
          relevance: { type: 'NUMBER' },
        },
        required: ['id', 'relevance'],
      },
    },
  },
  required: ['verdicts'],
};

const STRUCTURE_SYSTEM = `Tu structures les services d'un professionnel pour SBC Network, une application africaine francophone de mise en relation.
Le professionnel écrit librement ce qu'il sait faire. Renvoie :
- profession : son métier, au masculin singulier, en français courant (ex. "Coiffeur", "Plombier", "Graphiste").
- category : la famille de services (ex. "Locks", "Plomberie sanitaire", "Identité visuelle").
- services : un élément par prestation distincte qu'un client pourrait demander, nommée clairement (ex. "Réparation de locks"). Ne fusionne pas des prestations différentes, n'invente rien que le texte ne dit pas.
- synonyms : les autres mots qu'un client utiliserait pour la même prestation, y compris l'argot et les variantes locales (ex. locks, dreads, dreadlocks).
- specialties : les précisions mentionnées (ex. homme, femme, enfant, une technique). Vide si rien n'est dit.`;

const ANALYSIS_SYSTEM = `Tu analyses une demande de service pour SBC Network, une application africaine francophone qui transmet la demande aux professionnels pertinents.
Extrais uniquement ce que la personne a dit ; mets null ou [] pour le reste, sans deviner.
- profession : le métier probable du professionnel recherché (ex. "Coiffeur").
- service : la prestation précise demandée (ex. "Réparation de locks").
- mode : HOME (à domicile), ON_SITE (chez le professionnel), ONLINE (à distance), DELIVERY (livraison), ou null.
- budget : un montant entier en FCFA, ou null.
- desiredDate / desiredTime : tels que compris ("samedi", "14h").
- constraints : toute condition importante (ex. "femme uniquement", "matériel fourni").
Pose une clarificationQuestion courte UNIQUEMENT si la prestation elle-même est ambiguë au point que des professionnels différents seraient concernés (ex. "Vous cherchez une réparation ou une nouvelle pose ?"), avec 2 à 4 clarificationOptions. Jamais pour une date, un budget ou un lieu manquant. Si une réponse de clarification est fournie, intègre-la et ne repose pas de question.`;

const JUDGE_SYSTEM = `Tu vérifies si des services de professionnels répondent à une demande client sur SBC Network.
Pour chaque service candidat, donne relevance entre 0 et 1 : 1 = ce service réalise exactement la prestation demandée, 0.5 = proche ou partiel, 0 = autre métier ou autre prestation.
Juge uniquement la prestation, pas le lieu ni le prix.`;

/**
 * The three AI jobs of SBC Data. Each one has a non-AI fallback, because a
 * request must still reach professionals when Gemini is down or unconfigured.
 */
@Injectable()
export class SbcDataAiService {
  private readonly logger = new Logger(SbcDataAiService.name);

  constructor(private readonly gemini: GeminiClient) {}

  get enabled(): boolean {
    return this.gemini.enabled;
  }

  /** "je fais les dreads, pose de locks…" → proposals for the pro to validate (Data §4–5). */
  async structureServices(text: string): Promise<StructuredServices> {
    try {
      const raw = await this.gemini.generateJson<{
        profession: string;
        category: string;
        services: Array<{ name: string; synonyms: string[]; specialties: string[] }>;
      }>(STRUCTURE_SYSTEM, text, STRUCTURE_SCHEMA);
      const profession = clean(raw.profession);
      const category = clean(raw.category);
      return {
        profession,
        category,
        services: (raw.services ?? [])
          .filter((s) => clean(s.name))
          .map((s) => ({
            name: clean(s.name),
            category,
            profession,
            synonyms: cleanList(s.synonyms),
            specialties: cleanList(s.specialties),
          })),
      };
    } catch (err) {
      if (!(err instanceof GeminiUnavailableError)) throw err;
      this.logger.warn(`Structuring without AI: ${err.message}`);
      // Without AI each comma-separated item becomes a service as typed.
      const names = text
        .split(/[,;\n]+/)
        .map(clean)
        .filter(Boolean);
      return {
        profession: '',
        category: '',
        services: names.map((name) => ({
          name: capitalise(name),
          category: '',
          profession: '',
          synonyms: [],
          specialties: [],
        })),
      };
    }
  }

  /** Free text (+ an answer to our question, if any) → structured request (Data §7). */
  async analyzeRequest(
    text: string,
    clarificationAnswer?: string | null,
  ): Promise<RequestAnalysis> {
    const today = new Date().toLocaleDateString('fr-FR', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });
    const prompt = [
      `Nous sommes le ${today}.`,
      `Demande : """${text}"""`,
      clarificationAnswer
        ? `Réponse à la question de clarification : """${clarificationAnswer}"""`
        : '',
    ]
      .filter(Boolean)
      .join('\n');

    try {
      const raw = await this.gemini.generateJson<RequestAnalysis>(
        ANALYSIS_SYSTEM,
        prompt,
        ANALYSIS_SCHEMA,
      );
      const answered = Boolean(clarificationAnswer);
      const question = answered ? null : clean(raw.clarificationQuestion) || null;
      return {
        profession: clean(raw.profession) || null,
        service: clean(raw.service) || null,
        specialties: cleanList(raw.specialties),
        city: clean(raw.city) || null,
        district: clean(raw.district) || null,
        mode: raw.mode && MODES.includes(raw.mode) ? raw.mode : null,
        desiredDate: clean(raw.desiredDate) || null,
        desiredTime: clean(raw.desiredTime) || null,
        budget: Number.isInteger(raw.budget) && (raw.budget as number) > 0 ? raw.budget : null,
        constraints: cleanList(raw.constraints),
        clarificationQuestion: question,
        clarificationOptions: question ? cleanList(raw.clarificationOptions).slice(0, 4) : [],
      };
    } catch (err) {
      if (!(err instanceof GeminiUnavailableError)) throw err;
      this.logger.warn(`Analysing without AI: ${err.message}`);
      // The raw text still drives keyword matching; the requester fills the rest.
      return {
        profession: null,
        service: null,
        specialties: [],
        city: null,
        district: null,
        mode: null,
        desiredDate: null,
        desiredTime: null,
        budget: null,
        constraints: [],
        clarificationQuestion: null,
        clarificationOptions: [],
      };
    }
  }

  /**
   * Relevance 0–1 of each shortlisted service to the request. Only the
   * shortlist is sent, never the whole base (Data §8). Null = no AI verdict;
   * the caller then ranks on its own scores.
   */
  async judge(
    request: { rawText: string; service: string | null; specialties: string[] },
    candidates: JudgeCandidate[],
  ): Promise<Map<string, number> | null> {
    if (candidates.length === 0) return new Map();
    const prompt = JSON.stringify({
      demande: {
        texte: request.rawText,
        service: request.service,
        specialites: request.specialties,
      },
      candidats: candidates.map((c) => ({
        id: c.id,
        service: c.service,
        famille: c.category,
        metier: c.profession,
        specialites: c.specialties,
      })),
    });
    try {
      const raw = await this.gemini.generateJson<{
        verdicts: Array<{ id: string; relevance: number }>;
      }>(JUDGE_SYSTEM, prompt, JUDGE_SCHEMA);
      const known = new Set(candidates.map((c) => c.id));
      const out = new Map<string, number>();
      for (const v of raw.verdicts ?? []) {
        if (known.has(v.id)) out.set(v.id, Math.max(0, Math.min(1, Number(v.relevance) || 0)));
      }
      return out;
    } catch (err) {
      if (!(err instanceof GeminiUnavailableError)) throw err;
      this.logger.warn(`Matching without the AI judge: ${err.message}`);
      return null;
    }
  }

  /** Embeddings, or empty vectors when Gemini is unavailable. */
  async embed(
    texts: string[],
    task: 'RETRIEVAL_QUERY' | 'RETRIEVAL_DOCUMENT',
  ): Promise<number[][]> {
    try {
      return await this.gemini.embed(texts, task);
    } catch (err) {
      if (!(err instanceof GeminiUnavailableError)) throw err;
      this.logger.warn(`Embedding skipped: ${err.message}`);
      return texts.map(() => []);
    }
  }
}

function clean(value: unknown): string {
  return typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
}

function cleanList(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const v of values) {
    const c = clean(v);
    if (c && !seen.has(c.toLowerCase())) {
      seen.add(c.toLowerCase());
      out.push(c);
    }
  }
  return out;
}

function capitalise(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

import type { Tone } from '../components/ui';

export const REQUEST_STATUS: Record<string, { label: string; tone: Tone }> = {
  DRAFT: { label: 'Brouillon', tone: 'gray' },
  MATCHING: { label: 'Recherche', tone: 'orange' },
  SENT: { label: 'Envoyée', tone: 'orange' },
  RESPONDED: { label: 'Réponses reçues', tone: 'blue' },
  SELECTED: { label: 'Pro retenu', tone: 'blue' },
  COMPLETED: { label: 'Terminée', tone: 'green' },
  CANCELLED: { label: 'Annulée', tone: 'gray' },
  NO_MATCH: { label: 'Aucun pro', tone: 'red' },
  NO_RESPONSE: { label: 'Sans réponse', tone: 'red' },
};

export const DISPATCH_STATUS: Record<string, { label: string; tone: Tone }> = {
  SENT: { label: 'Non vue', tone: 'gray' },
  VIEWED: { label: 'Vue', tone: 'gray' },
  INTERESTED: { label: 'Proposition', tone: 'blue' },
  QUESTION: { label: 'Question', tone: 'orange' },
  UNAVAILABLE: { label: 'Pas dispo', tone: 'gray' },
  DECLINED: { label: 'Déclinée', tone: 'gray' },
  SELECTED: { label: 'Retenu', tone: 'green' },
  LOST: { label: 'Non retenu', tone: 'gray' },
};

export const MODE: Record<string, string> = {
  HOME: 'À domicile',
  ON_SITE: 'Sur place',
  ONLINE: 'En ligne',
  DELIVERY: 'Livraison',
};

export const MISSING: Record<string, string> = {
  profession: 'métier',
  description: 'description',
  city: 'ville',
  modes: 'mode de prestation',
  availability: 'disponibilité',
  shopUrl: 'lien SBC Shop',
  services: 'services',
};

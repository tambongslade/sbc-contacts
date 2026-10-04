import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const dateFmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });
const dateTimeFmt = new Intl.DateTimeFormat('fr-FR', {
  day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
});

export const fmtDate = (v?: string | null) => (v ? dateFmt.format(new Date(v)) : '—');
export const fmtDateTime = (v?: string | null) => (v ? dateTimeFmt.format(new Date(v)) : '—');
export const fcfa = (n?: number | null) =>
  n == null ? '—' : `${n.toLocaleString('fr-FR')} FCFA`;
export const pct = (r: number) => `${Math.round(r * 100)} %`;

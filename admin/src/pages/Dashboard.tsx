import { AlertTriangle, ClipboardList, Percent, Send, Tags, Users } from 'lucide-react';
import type { ComponentType } from 'react';
import { Card, ErrorNote, Loading, PageHeader } from '../components/ui';
import { api } from '../lib/api';
import { REQUEST_STATUS } from '../lib/labels';
import { useLoad } from '../lib/useLoad';
import { pct } from '../lib/utils';

interface Stats {
  requests: { total: number; last30Days: number; byStatus: Record<string, number> };
  pros: { total: number; receiving: number; services: number };
  dispatches: { total: number; answered: number; selected: number; responseRate: number; conversionRate: number };
  reports: number;
  topServices: Array<{ name: string; count: number }>;
  topCities: Array<{ name: string; count: number }>;
}

export function Dashboard() {
  const { data, error, loading } = useLoad(() => api<Stats>('/data/admin/stats'), []);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  if (!data) return null;
  const s = data;
  return (
    <>
      <PageHeader title="Tableau de bord" subtitle="Ce qui se passe sur les demandes et les professionnels." />
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <Kpi icon={ClipboardList} label="Demandes" value={s.requests.total} detail={`${s.requests.last30Days} ces 30 derniers jours`} href="#/requests" />
        <Kpi icon={Users} label="Professionnels" value={s.pros.total} detail={`${s.pros.receiving} avec réception active`} href="#/pros" />
        <Kpi icon={Tags} label="Services actifs" value={s.pros.services} href="#/services" />
        <Kpi icon={Send} label="Taux de réponse" value={pct(s.dispatches.responseRate)} detail={`${s.dispatches.answered} réponses sur ${s.dispatches.total} envois`} />
        <Kpi icon={Percent} label="Conversion" value={pct(s.dispatches.conversionRate)} detail={`${s.dispatches.selected} pros retenus`} />
        <Kpi icon={AlertTriangle} label="Signalements" value={s.reports} href="#/reports" warn={s.reports > 0} />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-3">
        <Card>
          <h2 className="mb-3 font-bold">Demandes par statut</h2>
          <RankList
            rows={Object.entries(s.requests.byStatus)
              .filter(([, n]) => n > 0)
              .sort((a, b) => b[1] - a[1])
              .map(([k, n]) => ({ name: REQUEST_STATUS[k]?.label ?? k, count: n }))}
          />
        </Card>
        <Card>
          <h2 className="mb-3 font-bold">Services les plus demandés</h2>
          <RankList rows={s.topServices} />
        </Card>
        <Card>
          <h2 className="mb-3 font-bold">Villes</h2>
          <RankList rows={s.topCities} />
        </Card>
      </div>
    </>
  );
}

function Kpi({ icon: Icon, label, value, detail, href, warn }: {
  icon: ComponentType<{ className?: string }>;
  label: string;
  value: number | string;
  detail?: string;
  href?: string;
  warn?: boolean;
}) {
  const body = (
    <Card className={href ? 'h-full transition-colors hover:border-primary' : 'h-full'}>
      <div className={`mb-3 inline-flex rounded-md p-2 ${warn ? 'bg-warning-soft text-warning' : 'bg-primary-soft text-primary'}`}>
        <Icon className="h-4 w-4" />
      </div>
      <p className="text-3xl font-extrabold tracking-tight">{value}</p>
      <p className="mt-1 text-sm font-semibold">{label}</p>
      {detail && <p className="mt-0.5 text-xs text-muted-foreground">{detail}</p>}
    </Card>
  );
  return href ? <a href={href} className="block">{body}</a> : body;
}

/** Ranked counts with a thin proportion bar; the number is always printed. */
function RankList({ rows }: { rows: Array<{ name: string; count: number }> }) {
  if (rows.length === 0) return <p className="text-sm text-muted-foreground">Pas encore de données.</p>;
  const max = Math.max(...rows.map((r) => r.count), 1);
  return (
    <ul className="space-y-3">
      {rows.map((r) => (
        <li key={r.name}>
          <div className="flex justify-between gap-3 text-sm">
            <span className="truncate">{r.name}</span>
            <span className="font-bold tabular-nums">{r.count}</span>
          </div>
          <div className="mt-1 h-1.5 rounded-full bg-muted">
            <div className="h-full rounded-full bg-primary" style={{ width: `${(r.count / max) * 100}%` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

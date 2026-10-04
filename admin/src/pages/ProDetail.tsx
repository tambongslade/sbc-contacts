import { ArrowLeft } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Badge, Button, Card, ErrorNote, Field, inputCls, Loading, PageHeader } from '../components/ui';
import { api } from '../lib/api';
import { DISPATCH_STATUS, MISSING, MODE, REQUEST_STATUS } from '../lib/labels';
import { useLoad } from '../lib/useLoad';
import { fcfa, fmtDate, fmtDateTime } from '../lib/utils';
import { ServiceEditor, type AdminService } from './Services';

interface ProDetailData {
  id: string;
  userId: string;
  profession: string;
  description: string;
  city: string;
  zones: string[];
  modes: string[];
  availability: string;
  priceMin: number | null;
  priceMax: number | null;
  shopUrl: string;
  whatsapp: string | null;
  receivingEnabled: boolean;
  receivingUntil: string | null;
  receivingActive: boolean;
  createdAt: string;
  missing: string[];
  user: { name: string | null; phoneNumber: string | null; email: string | null; country: string | null };
  services: Array<AdminService & { hasEmbedding: boolean }>;
  activity: Record<string, number>;
  recent: Array<{
    id: string;
    status: string;
    createdAt: string;
    request: { id: string; service: string | null; city: string | null; status: string };
  }>;
}

export function ProDetail({ userId }: { userId: string }) {
  const { data, error, loading, reload } = useLoad(() => api<ProDetailData>(`/data/admin/pros/${userId}`), [userId]);
  const [editing, setEditing] = useState<AdminService | null>(null);

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  if (!data) return null;
  const p = data;
  const received = Object.values(p.activity).reduce((a, b) => a + b, 0);

  return (
    <>
      <a href="#/pros" className="mb-4 inline-flex items-center gap-1 text-sm font-semibold text-primary hover:underline">
        <ArrowLeft className="h-4 w-4" aria-hidden /> Professionnels
      </a>
      <PageHeader
        title={p.user.name ?? 'Professionnel'}
        subtitle={`${p.profession} · ${p.city} · pro depuis le ${fmtDate(p.createdAt)}`}
        actions={p.missing.length ? <Badge tone="orange">Profil incomplet</Badge> : <Badge tone="green">Profil complet</Badge>}
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <Receiving pro={p} onSaved={reload} />
        <Card className="lg:col-span-2">
          <h2 className="mb-3 font-bold">Profil</h2>
          {p.missing.length > 0 && (
            <p className="mb-3 rounded-md bg-warning-soft px-3 py-2 text-sm font-semibold text-warning">
              Manque : {p.missing.map((m) => MISSING[m] ?? m).join(', ')} — aucune demande ne peut lui arriver.
            </p>
          )}
          <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
            <Fact k="Téléphone / WhatsApp" v={p.whatsapp ?? p.user.phoneNumber} />
            <Fact k="E-mail" v={p.user.email} />
            <Fact k="Zones" v={[p.city, ...p.zones].join(', ')} />
            <Fact k="Prestation" v={p.modes.map((m) => MODE[m] ?? m).join(', ')} />
            <Fact k="Disponibilité" v={p.availability} />
            <Fact k="Prix" v={p.priceMin || p.priceMax ? [p.priceMin, p.priceMax].map((x) => (x ? fcfa(x) : '…')).join(' – ') : null} />
          </dl>
          <p className="mt-3 text-sm text-muted-foreground">{p.description}</p>
          <a href={p.shopUrl} target="_blank" rel="noreferrer" className="mt-3 inline-block text-sm font-semibold text-primary hover:underline">
            Boutique SBC Shop ↗
          </a>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <h2 className="mb-3 font-bold">Services ({p.services.length})</h2>
          {p.services.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucun service : ce professionnel est invisible pour le matching.</p>
          ) : (
            <ul className="divide-y divide-border">
              {p.services.map((s) => (
                <li key={s.id} className="flex items-start justify-between gap-3 py-3">
                  <div>
                    <p className="font-semibold">
                      {s.name} {!s.isActive && <Badge>désactivé</Badge>}
                    </p>
                    <p className="text-xs text-muted-foreground">{s.category} · {s.profession}</p>
                    {s.synonyms.length > 0 && <p className="mt-1 text-xs text-muted-foreground">Synonymes : {s.synonyms.join(', ')}</p>}
                  </div>
                  <Button variant="outline" onClick={() => setEditing(s)}>Corriger</Button>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <h2 className="mb-3 font-bold">Activité</h2>
          <p className="text-3xl font-extrabold">{received}</p>
          <p className="text-sm text-muted-foreground">demandes reçues</p>
          <ul className="mt-3 space-y-1 text-sm">
            {Object.entries(p.activity).map(([k, n]) => (
              <li key={k} className="flex justify-between">
                <span>{DISPATCH_STATUS[k]?.label ?? k}</span>
                <span className="font-bold tabular-nums">{n}</span>
              </li>
            ))}
          </ul>
        </Card>
      </div>

      {p.recent.length > 0 && (
        <Card className="mt-4">
          <h2 className="mb-3 font-bold">Dernières demandes reçues</h2>
          <ul className="divide-y divide-border">
            {p.recent.map((d) => (
              <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                <a href={`#/requests/${d.request.id}`} className="font-semibold text-primary hover:underline">
                  {d.request.service ?? 'Demande'} {d.request.city ? `· ${d.request.city}` : ''}
                </a>
                <span className="flex items-center gap-2">
                  <span className="text-xs text-muted-foreground">{fmtDateTime(d.createdAt)}</span>
                  <Badge tone={DISPATCH_STATUS[d.status]?.tone}>{DISPATCH_STATUS[d.status]?.label ?? d.status}</Badge>
                  <Badge tone={REQUEST_STATUS[d.request.status]?.tone}>{REQUEST_STATUS[d.request.status]?.label}</Badge>
                </span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <ServiceEditor
        service={editing}
        siblings={p.services}
        onClose={() => setEditing(null)}
        onChanged={() => (setEditing(null), reload())}
      />
    </>
  );
}

/** Reception on/off and its end date — the subscription until payments exist. */
function Receiving({ pro, onSaved }: { pro: ProDetailData; onSaved: () => void }) {
  const [enabled, setEnabled] = useState(pro.receivingEnabled);
  const [until, setUntil] = useState(pro.receivingUntil?.slice(0, 10) ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  useEffect(() => {
    setEnabled(pro.receivingEnabled);
    setUntil(pro.receivingUntil?.slice(0, 10) ?? '');
  }, [pro]);

  const plus30 = () => {
    const base = until && new Date(until) > new Date() ? new Date(until) : new Date();
    base.setDate(base.getDate() + 30);
    setEnabled(true);
    setUntil(base.toISOString().slice(0, 10));
  };

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await api(`/data/admin/pros/${pro.userId}/receiving`, {
        method: 'PATCH',
        body: { enabled, ...(until ? { until: new Date(`${until}T23:59:59`).toISOString() } : {}) },
      });
      onSaved();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card>
      <h2 className="mb-1 font-bold">Abonnement Pro</h2>
      <p className="mb-4 text-sm text-muted-foreground">2 000 FCFA/mois · réception des demandes</p>
      <div className="mb-3">
        {pro.receivingActive ? <Badge tone="green">Actif</Badge> : <Badge tone="gray">Inactif</Badge>}
      </div>
      <label className="mb-3 flex cursor-pointer items-center gap-3 text-sm font-semibold">
        <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="h-5 w-5 accent-[hsl(var(--primary))]" />
        Réception des demandes activée
      </label>
      <Field label="Fin des droits" hint="Vide = sans limite">
        <input type="date" value={until} onChange={(e) => setUntil(e.target.value)} className={inputCls} />
      </Field>
      {error ? <div className="mt-3"><ErrorNote error={error} /></div> : null}
      <div className="mt-4 flex gap-2">
        <Button variant="outline" onClick={plus30}>+ 30 jours</Button>
        <Button busy={busy} onClick={save}>Enregistrer</Button>
      </div>
    </Card>
  );
}

function Fact({ k, v }: { k: string; v?: string | null }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{k}</dt>
      <dd className="font-semibold">{v || '—'}</dd>
    </div>
  );
}

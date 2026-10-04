import { ArrowLeft, Ban } from 'lucide-react';
import { useState } from 'react';
import { Badge, Button, Card, Cell, ErrorNote, Loading, Modal, PageHeader, Table } from '../components/ui';
import { api } from '../lib/api';
import { DISPATCH_STATUS, MODE, REQUEST_STATUS } from '../lib/labels';
import { useLoad } from '../lib/useLoad';
import { fcfa, fmtDateTime } from '../lib/utils';

interface Detail {
  id: string;
  rawText: string;
  status: string;
  profession: string | null;
  service: string | null;
  specialties: string[];
  city: string | null;
  district: string | null;
  mode: string | null;
  desiredDate: string | null;
  desiredTime: string | null;
  budget: number | null;
  constraints: string[];
  clarificationQuestion: string | null;
  clarificationAnswer: string | null;
  createdAt: string;
  sentAt: string | null;
  completedAt: string | null;
  wasPerformed: boolean | null;
  hiddenAt: string | null;
  user: { id: string; name: string | null; phoneNumber: string | null; email: string | null };
  dispatches: Array<{
    id: string;
    score: number;
    status: string;
    price: number | null;
    availability: string | null;
    message: string | null;
    reasons: {
      keyword: number;
      semantic: number;
      profession: boolean;
      relevance: number | null;
      location: string;
    } | null;
    service: { name: string } | null;
    pro: { userId: string; profession: string; city: string; user: { name: string | null } };
  }>;
  reports: Array<{ id: string; createdAt: string; metadata: { comment?: string | null } | null }>;
}

export function RequestDetail({ id }: { id: string }) {
  const { data, error, loading, setData } = useLoad(() => api<Detail>(`/data/admin/requests/${id}`), [id]);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<unknown>(null);

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} />;
  if (!data) return null;
  const r = data;
  const open = !['COMPLETED', 'CANCELLED'].includes(r.status);

  const suspend = async () => {
    setBusy(true);
    try {
      setData(await api<Detail>(`/data/admin/requests/${id}/suspend`, { method: 'POST' }));
      setConfirm(false);
    } catch (e) {
      setActionError(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <a href="#/requests" className="mb-4 inline-flex items-center gap-1 text-sm font-semibold text-primary hover:underline">
        <ArrowLeft className="h-4 w-4" aria-hidden /> Demandes
      </a>
      <PageHeader
        title={r.service ?? 'Demande'}
        subtitle={`Créée le ${fmtDateTime(r.createdAt)} par ${r.user.name ?? 'un membre'}`}
        actions={
          <div className="flex items-center gap-3">
            <Badge tone={REQUEST_STATUS[r.status]?.tone}>{REQUEST_STATUS[r.status]?.label ?? r.status}</Badge>
            {open && (
              <Button variant="outline" onClick={() => setConfirm(true)}>
                <Ban className="h-4 w-4" aria-hidden /> Suspendre
              </Button>
            )}
          </div>
        }
      />
      {actionError ? <div className="mb-4"><ErrorNote error={actionError} /></div> : null}

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <h2 className="mb-2 font-bold">Ce que le membre a écrit</h2>
          <p className="rounded-md bg-muted px-4 py-3 text-sm">« {r.rawText} »</p>
          <h2 className="mb-2 mt-5 font-bold">Ce que l'IA a compris</h2>
          <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
            <Fact k="Métier" v={r.profession} />
            <Fact k="Service" v={r.service} />
            <Fact k="Lieu" v={[r.district, r.city].filter(Boolean).join(', ')} />
            <Fact k="Prestation" v={r.mode ? MODE[r.mode] : null} />
            <Fact k="Date" v={[r.desiredDate, r.desiredTime].filter(Boolean).join(' à ')} />
            <Fact k="Budget" v={r.budget ? fcfa(r.budget) : null} />
            {r.specialties.length > 0 && <Fact k="Spécialités" v={r.specialties.join(', ')} />}
            {r.constraints.length > 0 && <Fact k="Conditions" v={r.constraints.join(', ')} />}
          </dl>
          {r.clarificationQuestion && (
            <p className="mt-4 text-sm text-muted-foreground">
              Question posée : « {r.clarificationQuestion} » → <strong className="text-foreground">{r.clarificationAnswer ?? 'sans réponse'}</strong>
            </p>
          )}
        </Card>
        <Card>
          <h2 className="mb-2 font-bold">Demandeur</h2>
          <p className="font-semibold">{r.user.name ?? '—'}</p>
          <p className="text-sm text-muted-foreground">{r.user.phoneNumber ?? ''}</p>
          <p className="text-sm text-muted-foreground">{r.user.email ?? ''}</p>
          <dl className="mt-4 space-y-1 text-sm">
            <Fact k="Envoyée" v={fmtDateTime(r.sentAt)} />
            <Fact k="Terminée" v={r.completedAt ? `${fmtDateTime(r.completedAt)} · ${r.wasPerformed ? 'réalisée' : 'non réalisée'}` : null} />
            {r.hiddenAt && <Fact k="Supprimée" v={`par le membre, ${fmtDateTime(r.hiddenAt)}`} />}
          </dl>
        </Card>
      </div>

      <h2 className="mb-2 mt-8 text-lg font-bold">Envoyée à {r.dispatches.length} professionnel{r.dispatches.length > 1 ? 's' : ''}</h2>
      <p className="mb-3 text-sm text-muted-foreground">
        Pourquoi chacun a été choisi : correspondance des mots, proximité de sens, avis de l'IA sur la pertinence, et lieu.
      </p>
      {r.dispatches.length === 0 ? (
        <Card><p className="text-sm text-muted-foreground">Aucun professionnel ne correspondait.</p></Card>
      ) : (
        <Table head={['Professionnel', 'Service', 'Score', 'Mots', 'Sens', 'IA', 'Lieu', 'Réponse']}>
          {r.dispatches.map((d) => (
            <tr key={d.id}>
              <Cell>
                <a href={`#/pros/${d.pro.userId}`} className="font-semibold text-primary hover:underline">{d.pro.user.name ?? d.pro.profession}</a>
                <p className="text-xs text-muted-foreground">{d.pro.profession} · {d.pro.city}</p>
              </Cell>
              <Cell>{d.service?.name ?? '—'}</Cell>
              <Cell className="font-bold tabular-nums">{d.score.toFixed(2)}</Cell>
              <Cell className="tabular-nums">{d.reasons ? `${Math.round(d.reasons.keyword * 100)} %` : '—'}</Cell>
              <Cell className="tabular-nums">{d.reasons ? d.reasons.semantic.toFixed(2) : '—'}</Cell>
              <Cell className="tabular-nums">{d.reasons?.relevance != null ? d.reasons.relevance.toFixed(2) : 'n/a'}</Cell>
              <Cell>{d.reasons?.location ?? '—'}</Cell>
              <Cell>
                <Badge tone={DISPATCH_STATUS[d.status]?.tone}>{DISPATCH_STATUS[d.status]?.label ?? d.status}</Badge>
                {(d.price || d.availability) && (
                  <p className="mt-1 text-xs text-muted-foreground">{[d.price ? fcfa(d.price) : null, d.availability].filter(Boolean).join(' · ')}</p>
                )}
              </Cell>
            </tr>
          ))}
        </Table>
      )}

      {r.reports.length > 0 && (
        <>
          <h2 className="mb-3 mt-8 text-lg font-bold">Signalements</h2>
          <div className="space-y-2">
            {r.reports.map((rep) => (
              <Card key={rep.id} className="border-warning/40">
                <p className="text-xs text-muted-foreground">{fmtDateTime(rep.createdAt)}</p>
                <p className="mt-1 text-sm">{rep.metadata?.comment ?? 'Prestation non réalisée (sans commentaire).'}</p>
              </Card>
            ))}
          </div>
        </>
      )}

      <Modal
        open={confirm}
        onClose={() => setConfirm(false)}
        title="Suspendre cette demande ?"
        footer={
          <>
            <Button variant="outline" onClick={() => setConfirm(false)}>Annuler</Button>
            <Button variant="danger" busy={busy} onClick={suspend}>Suspendre</Button>
          </>
        }
      >
        <p className="text-sm text-muted-foreground">
          Elle passe en « Annulée » : les professionnels qui l'ont reçue ne peuvent plus y répondre. L'action est enregistrée à ton nom.
        </p>
      </Modal>
    </>
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

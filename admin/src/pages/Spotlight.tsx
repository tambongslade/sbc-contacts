import { useEffect, useState } from 'react';
import { Badge, Button, Cell, Empty, ErrorNote, Field, inputCls, Loading, Modal, PageHeader, Pager, Row, SearchInput, Table, Tabs } from '../components/ui';
import { api, type Page } from '../lib/api';
import { useLoad } from '../lib/useLoad';
import { fmtDate } from '../lib/utils';

interface SpotlightRow {
  userId: string;
  name: string | null;
  phoneNumber: string | null;
  email: string | null;
  country: string | null;
  avatarUrl: string | null;
  spotlightUntil: string | null;
  active: boolean;
  source: 'sbc' | 'admin' | null;
}

/**
 * "Mise en avant": the member shows at the top of "Qui m'a enregistré" and
 * "Augmenter mes vues WhatsApp" for everyone who has not saved them yet.
 * Paid on SBC (3 000 FCFA/mois); switched on here by hand meanwhile.
 */
export function Spotlight() {
  const [search, setSearch] = useState('');
  const [featured, setFeatured] = useState<'' | 'on' | 'off'>('on');
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<SpotlightRow | null>(null);
  const { data, error, loading, reload } = useLoad(
    () => api<Page<SpotlightRow>>('/spotlight/admin', { query: { search, featured, page, limit: 25 } }),
    [search, featured, page],
  );

  return (
    <>
      <PageHeader
        title="Mise en avant"
        subtitle="Membres affichés « En vedette » en haut de « Qui m'a enregistré » et « Augmenter mes vues ». 3 000 FCFA/mois."
      />
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={search} onChange={(v) => (setSearch(v), setPage(1))} placeholder="Nom, e-mail, téléphone" />
        <Tabs
          value={featured}
          onChange={(v) => (setFeatured(v), setPage(1))}
          options={[
            { value: 'on', label: 'En vedette' },
            { value: 'off', label: 'Pas en vedette' },
            { value: '', label: 'Tous' },
          ]}
        />
      </div>
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data && data.items.length === 0 ? (
        <Empty>{featured === 'on' && !search ? 'Personne en vedette pour le moment. Cherche un membre dans « Tous » pour l’activer.' : 'Aucun membre.'}</Empty>
      ) : data ? (
        <>
          <Table head={['Membre', 'Pays', 'Mise en avant', '']}>
            {data.items.map((m) => (
              <Row key={m.userId}>
                <Cell>
                  <p className="font-semibold">{m.name ?? '—'}</p>
                  <p className="text-xs text-muted-foreground">{[m.phoneNumber, m.email].filter(Boolean).join(' · ') || '—'}</p>
                  {!m.phoneNumber && <p className="text-xs font-semibold text-warning">Sans numéro : ne peut pas être affiché</p>}
                </Cell>
                <Cell>{m.country ?? '—'}</Cell>
                <Cell><Status row={m} /></Cell>
                <Cell className="text-right">
                  <Button variant="outline" onClick={() => setEditing(m)}>{m.spotlightUntil && m.active ? 'Modifier' : 'Activer'}</Button>
                </Cell>
              </Row>
            ))}
          </Table>
          <Pager page={data.page} totalPages={data.totalPages} onPage={setPage} />
        </>
      ) : null}
      <SpotlightEditor member={editing} onClose={() => setEditing(null)} onSaved={() => (setEditing(null), reload())} />
    </>
  );
}

function Status({ row }: { row: SpotlightRow }) {
  if (row.source === 'sbc') return <Badge tone="green">Payé sur SBC</Badge>;
  if (row.source === 'admin') return <Badge tone="green">Jusqu’au {fmtDate(row.spotlightUntil)}</Badge>;
  if (row.spotlightUntil) return <Badge tone="orange">Expiré le {fmtDate(row.spotlightUntil)}</Badge>;
  return <Badge>Inactif</Badge>;
}

const dayPlus = (from: string, days: number) => {
  const base = from && new Date(from) > new Date() ? new Date(from) : new Date();
  base.setDate(base.getDate() + days);
  return base.toISOString().slice(0, 10);
};

function SpotlightEditor({ member, onClose, onSaved }: { member: SpotlightRow | null; onClose: () => void; onSaved: () => void }) {
  const [until, setUntil] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  useEffect(() => {
    setError(null);
    setUntil(member?.spotlightUntil && member.active ? member.spotlightUntil.slice(0, 10) : dayPlus('', 30));
  }, [member]);

  const save = async (value: string | null) => {
    if (!member) return;
    setBusy(true);
    setError(null);
    try {
      await api(`/spotlight/admin/${member.userId}`, {
        method: 'PUT',
        body: { until: value ? new Date(`${value}T23:59:59`).toISOString() : null },
      });
      onSaved();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open={member !== null}
      onClose={onClose}
      title={`Mise en avant · ${member?.name ?? 'Membre'}`}
      footer={
        <>
          {member?.spotlightUntil && member.source === 'admin' && (
            <Button variant="danger" busy={busy} onClick={() => save(null)}>Arrêter</Button>
          )}
          <Button busy={busy} disabled={!until} onClick={() => save(until)}>Enregistrer</Button>
        </>
      }
    >
      {member?.source === 'sbc' && (
        <p className="rounded-md bg-success-soft px-3 py-2 text-sm font-semibold text-success">
          Déjà payé sur SBC : la mise en avant reste active tant que SBC la renouvelle.
        </p>
      )}
      <Field label="En vedette jusqu’au">
        <input type="date" value={until} min={new Date().toISOString().slice(0, 10)} onChange={(e) => setUntil(e.target.value)} className={inputCls} />
      </Field>
      <div className="flex gap-2">
        <Button variant="outline" onClick={() => setUntil(dayPlus(until, 7))}>+ 7 jours</Button>
        <Button variant="outline" onClick={() => setUntil(dayPlus(until, 30))}>+ 30 jours</Button>
      </div>
      {error ? <ErrorNote error={error} /> : null}
    </Modal>
  );
}

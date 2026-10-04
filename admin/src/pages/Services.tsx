import { useEffect, useState } from 'react';
import { Badge, Button, Cell, Empty, ErrorNote, Field, inputCls, Loading, Modal, PageHeader, Pager, Row, SearchInput, Table } from '../components/ui';
import { api, type Page } from '../lib/api';
import { useLoad } from '../lib/useLoad';

export interface AdminService {
  id: string;
  proId?: string;
  name: string;
  category: string;
  profession: string;
  synonyms: string[];
  specialties: string[];
  isActive: boolean;
}

interface ServiceRow extends AdminService {
  requestsMatched: number;
  hasEmbedding: boolean;
  pro: { userId: string; city: string; user: { name: string | null } };
}

export function Services() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<ServiceRow | null>(null);
  const [siblings, setSiblings] = useState<AdminService[]>([]);
  const { data, error, loading, reload } = useLoad(
    () => api<Page<ServiceRow>>('/data/admin/services', { query: { search, page, limit: 30 } }),
    [search, page],
  );

  // Merging only makes sense between services of the same pro.
  useEffect(() => {
    if (!editing) return;
    api<{ services: AdminService[] }>(`/data/admin/pros/${editing.pro.userId}`)
      .then((p) => setSiblings(p.services))
      .catch(() => setSiblings([]));
  }, [editing]);

  return (
    <>
      <PageHeader title="Services" subtitle="Corriger une classification, ajouter des synonymes, fusionner ou supprimer." />
      <div className="mb-4">
        <SearchInput value={search} onChange={(v) => (setSearch(v), setPage(1))} placeholder="Service, catégorie, métier, synonyme, pro" />
      </div>
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data && data.items.length === 0 ? (
        <Empty>Aucun service.</Empty>
      ) : data ? (
        <>
          <Table head={['Service', 'Métier', 'Professionnel', 'Synonymes', 'Demandes', 'État']}>
            {data.items.map((s) => (
              <Row key={s.id} onOpen={() => setEditing(s)}>
                <Cell>
                  <p className="font-semibold">{s.name}</p>
                  <p className="text-xs text-muted-foreground">{s.category}</p>
                </Cell>
                <Cell>{s.profession}</Cell>
                <Cell>
                  <a href={`#/pros/${s.pro.userId}`} onClick={(e) => e.stopPropagation()} className="font-semibold text-primary hover:underline">
                    {s.pro.user.name ?? '—'}
                  </a>
                  <p className="text-xs text-muted-foreground">{s.pro.city}</p>
                </Cell>
                <Cell className="max-w-xs"><span className="line-clamp-2 text-xs text-muted-foreground">{s.synonyms.join(', ') || '—'}</span></Cell>
                <Cell className="tabular-nums">{s.requestsMatched}</Cell>
                <Cell>
                  {s.isActive ? <Badge tone="green">Actif</Badge> : <Badge>Désactivé</Badge>}
                  {!s.hasEmbedding && <p className="mt-1 text-xs text-warning" title="Sans vecteur, seule la recherche par mots-clés le trouve">sans vecteur</p>}
                </Cell>
              </Row>
            ))}
          </Table>
          <Pager page={data.page} totalPages={data.totalPages} onPage={setPage} />
        </>
      ) : null}
      <ServiceEditor service={editing} siblings={siblings} onClose={() => setEditing(null)} onChanged={() => (setEditing(null), reload())} />
    </>
  );
}

/** Correct, merge or delete one service. Shared with the pro page. */
export function ServiceEditor({ service, siblings, onClose, onChanged }: {
  service: AdminService | null;
  siblings: AdminService[];
  onClose: () => void;
  onChanged: () => void;
}) {
  const [form, setForm] = useState({ name: '', category: '', profession: '', synonyms: '', specialties: '', isActive: true });
  const [mergeInto, setMergeInto] = useState('');
  const [busy, setBusy] = useState<'' | 'save' | 'merge' | 'delete'>('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    if (!service) return;
    setForm({
      name: service.name,
      category: service.category,
      profession: service.profession,
      synonyms: service.synonyms.join(', '),
      specialties: service.specialties.join(', '),
      isActive: service.isActive,
    });
    setMergeInto('');
    setConfirmDelete(false);
    setError(null);
  }, [service]);

  if (!service) return null;
  const list = (s: string) => s.split(',').map((x) => x.trim()).filter(Boolean);
  const others = siblings.filter((s) => s.id !== service.id);

  const run = async (kind: 'save' | 'merge' | 'delete', call: () => Promise<unknown>) => {
    setBusy(kind);
    setError(null);
    try {
      await call();
      onChanged();
    } catch (e) {
      setError(e);
    } finally {
      setBusy('');
    }
  };

  return (
    <Modal
      open={Boolean(service)}
      onClose={onClose}
      title="Corriger le service"
      footer={
        <>
          <Button variant="outline" onClick={onClose}>Fermer</Button>
          <Button
            busy={busy === 'save'}
            disabled={form.name.trim().length < 2}
            onClick={() =>
              run('save', () =>
                api(`/data/admin/services/${service.id}`, {
                  method: 'PATCH',
                  body: {
                    name: form.name,
                    category: form.category,
                    profession: form.profession,
                    synonyms: list(form.synonyms),
                    specialties: list(form.specialties),
                    isActive: form.isActive,
                  },
                }),
              )
            }
          >
            Enregistrer
          </Button>
        </>
      }
    >
      <Field label="Nom du service">
        <input className={inputCls} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Catégorie">
          <input className={inputCls} value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })} />
        </Field>
        <Field label="Métier">
          <input className={inputCls} value={form.profession} onChange={(e) => setForm({ ...form, profession: e.target.value })} />
        </Field>
      </div>
      <Field label="Synonymes" hint="Séparés par des virgules. Jamais montrés au pro ; ils aident la recherche.">
        <textarea rows={2} className={`${inputCls} h-auto py-2`} value={form.synonyms} onChange={(e) => setForm({ ...form, synonyms: e.target.value })} />
      </Field>
      <Field label="Spécialités" hint="Séparées par des virgules.">
        <input className={inputCls} value={form.specialties} onChange={(e) => setForm({ ...form, specialties: e.target.value })} />
      </Field>
      <label className="flex cursor-pointer items-center gap-3 text-sm font-semibold">
        <input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} className="h-5 w-5 accent-[hsl(var(--primary))]" />
        Service actif (reçoit des demandes)
      </label>

      {others.length > 0 && (
        <div className="rounded-lg border border-border p-3">
          <p className="mb-2 text-sm font-bold">Fusionner avec un autre service du même pro</p>
          <div className="flex gap-2">
            <select className={inputCls} value={mergeInto} onChange={(e) => setMergeInto(e.target.value)} aria-label="Service cible">
              <option value="">Choisir le service à garder…</option>
              {others.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
            </select>
            <Button
              variant="outline"
              disabled={!mergeInto}
              busy={busy === 'merge'}
              onClick={() => run('merge', () => api(`/data/admin/services/${service.id}/merge`, { method: 'POST', body: { intoId: mergeInto } }))}
            >
              Fusionner
            </Button>
          </div>
          <p className="mt-1 text-xs text-muted-foreground">Ses synonymes et son historique rejoignent le service choisi ; celui-ci est supprimé.</p>
        </div>
      )}

      <div className="flex items-center justify-between rounded-lg bg-destructive-soft p-3">
        <p className="text-sm font-semibold text-destructive">Supprimer ce service</p>
        {confirmDelete ? (
          <Button variant="danger" busy={busy === 'delete'} onClick={() => run('delete', () => api(`/data/admin/services/${service.id}`, { method: 'DELETE' }))}>
            Confirmer
          </Button>
        ) : (
          <Button variant="outline" onClick={() => setConfirmDelete(true)}>Supprimer</Button>
        )}
      </div>
      {error ? <ErrorNote error={error} /> : null}
    </Modal>
  );
}

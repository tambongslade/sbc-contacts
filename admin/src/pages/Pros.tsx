import { useState } from 'react';
import { Badge, Cell, Empty, ErrorNote, Loading, PageHeader, Pager, Row, SearchInput, Table, Tabs } from '../components/ui';
import { api, type Page } from '../lib/api';
import { MISSING } from '../lib/labels';
import { go } from '../lib/router';
import { useLoad } from '../lib/useLoad';
import { fmtDate } from '../lib/utils';

export interface ProRow {
  userId: string;
  name: string | null;
  phoneNumber: string | null;
  profession: string;
  city: string;
  receivingActive: boolean;
  receivingEnabled: boolean;
  receivingUntil: string | null;
  services: string[];
  requestsReceived: number;
  missing: string[];
}

export function Pros() {
  const [search, setSearch] = useState('');
  const [receiving, setReceiving] = useState<'' | 'on' | 'off'>('');
  const [page, setPage] = useState(1);
  const { data, error, loading } = useLoad(
    () => api<Page<ProRow>>('/data/admin/pros', { query: { search, receiving, page, limit: 25 } }),
    [search, receiving, page],
  );

  return (
    <>
      <PageHeader title="Professionnels" subtitle="Profils, services, abonnement et activité." />
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={search} onChange={(v) => (setSearch(v), setPage(1))} placeholder="Nom, métier, ville, téléphone" />
        <Tabs
          value={receiving}
          onChange={(v) => (setReceiving(v), setPage(1))}
          options={[
            { value: '', label: 'Tous' },
            { value: 'on', label: 'Réception active' },
            { value: 'off', label: 'Sans réception' },
          ]}
        />
      </div>
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data && data.items.length === 0 ? (
        <Empty>Aucun professionnel.</Empty>
      ) : data ? (
        <>
          <Table head={['Professionnel', 'Ville', 'Services', 'Demandes reçues', 'Abonnement', 'Profil']}>
            {data.items.map((p) => (
              <Row key={p.userId} onOpen={() => go(`/pros/${p.userId}`)}>
                <Cell>
                  <p className="font-semibold">{p.name ?? '—'}</p>
                  <p className="text-xs text-muted-foreground">{p.profession} · {p.phoneNumber ?? ''}</p>
                </Cell>
                <Cell>{p.city}</Cell>
                <Cell className="max-w-xs">
                  <span className="line-clamp-2 text-xs">{p.services.join(', ') || <span className="text-muted-foreground">aucun</span>}</span>
                </Cell>
                <Cell className="tabular-nums">{p.requestsReceived}</Cell>
                <Cell>
                  {p.receivingActive ? (
                    <Badge tone="green">Actif{p.receivingUntil ? ` · ${fmtDate(p.receivingUntil)}` : ''}</Badge>
                  ) : (
                    <Badge tone={p.receivingEnabled ? 'orange' : 'gray'}>{p.receivingEnabled ? 'Expiré' : 'Inactif'}</Badge>
                  )}
                </Cell>
                <Cell>
                  {p.missing.length === 0 ? (
                    <Badge tone="green">Complet</Badge>
                  ) : (
                    <span title={`Manque : ${p.missing.map((m) => MISSING[m] ?? m).join(', ')}`}>
                      <Badge tone="orange">Incomplet ({p.missing.length})</Badge>
                    </span>
                  )}
                </Cell>
              </Row>
            ))}
          </Table>
          <Pager page={data.page} totalPages={data.totalPages} onPage={setPage} />
        </>
      ) : null}
    </>
  );
}

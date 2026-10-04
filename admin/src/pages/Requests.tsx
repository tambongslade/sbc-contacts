import { useState } from 'react';
import { Badge, Cell, Empty, ErrorNote, Loading, PageHeader, Pager, Row, SearchInput, Table, Tabs } from '../components/ui';
import { api, type Page } from '../lib/api';
import { REQUEST_STATUS } from '../lib/labels';
import { go } from '../lib/router';
import { useLoad } from '../lib/useLoad';
import { fmtDateTime } from '../lib/utils';

interface RequestRow {
  id: string;
  rawText: string;
  service: string | null;
  city: string | null;
  status: string;
  createdAt: string;
  hiddenAt: string | null;
  user: { name: string | null };
  dispatchedCount: number;
  answeredCount: number;
}

const FILTERS = [
  { value: '', label: 'Toutes' },
  { value: 'SENT', label: 'Envoyées' },
  { value: 'RESPONDED', label: 'Réponses' },
  { value: 'SELECTED', label: 'Pro retenu' },
  { value: 'COMPLETED', label: 'Terminées' },
  { value: 'NO_MATCH', label: 'Aucun pro' },
  { value: 'CANCELLED', label: 'Annulées' },
];

export function Requests() {
  const [status, setStatus] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const { data, error, loading } = useLoad(
    () => api<Page<RequestRow>>('/data/admin/requests', { query: { status, search, page, limit: 25 } }),
    [status, search, page],
  );

  return (
    <>
      <PageHeader title="Demandes" subtitle="Toutes les demandes des membres, et à qui elles ont été envoyées." />
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={search} onChange={(v) => (setSearch(v), setPage(1))} placeholder="Rechercher un service, une ville, un membre" />
        <Tabs value={status} onChange={(v) => (setStatus(v), setPage(1))} options={FILTERS} />
      </div>
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data && data.items.length === 0 ? (
        <Empty>Aucune demande.</Empty>
      ) : data ? (
        <>
          <Table head={['Date', 'Demande', 'Ville', 'Demandeur', 'Envoyée à', 'Statut']}>
            {data.items.map((r) => (
              <Row key={r.id} onOpen={() => go(`/requests/${r.id}`)}>
                <Cell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(r.createdAt)}</Cell>
                <Cell>
                  <p className="font-semibold">{r.service ?? '—'}</p>
                  <p className="line-clamp-1 max-w-md text-xs text-muted-foreground">{r.rawText}</p>
                </Cell>
                <Cell>{r.city ?? '—'}</Cell>
                <Cell>{r.user.name ?? '—'}</Cell>
                <Cell className="tabular-nums">
                  {r.dispatchedCount} pro{r.dispatchedCount > 1 ? 's' : ''}
                  <span className="text-muted-foreground"> · {r.answeredCount} rép.</span>
                </Cell>
                <Cell>
                  <div className="flex flex-col items-start gap-1">
                    <Badge tone={REQUEST_STATUS[r.status]?.tone}>{REQUEST_STATUS[r.status]?.label ?? r.status}</Badge>
                    {r.hiddenAt && <span className="text-xs text-muted-foreground">supprimée par le membre</span>}
                  </div>
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

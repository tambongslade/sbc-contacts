import { useState } from 'react';
import { Cell, Empty, ErrorNote, Loading, PageHeader, Pager, Table } from '../components/ui';
import { api, type Page } from '../lib/api';
import { useLoad } from '../lib/useLoad';
import { fmtDateTime } from '../lib/utils';

interface Report {
  id: string;
  createdAt: string;
  comment: string | null;
  request: { id: string; service: string | null; city: string | null } | null;
  pro: { userId: string; name: string | null; profession: string } | null;
  reporter: { id: string; name: string | null; phoneNumber: string | null } | null;
}

export function Reports() {
  const [page, setPage] = useState(1);
  const { data, error, loading } = useLoad(() => api<Page<Report>>('/data/admin/reports', { query: { page, limit: 25 } }), [page]);
  return (
    <>
      <PageHeader title="Signalements" subtitle="Prestations déclarées non réalisées par les membres." />
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data && data.items.length === 0 ? (
        <Empty>Aucun signalement pour l'instant.</Empty>
      ) : data ? (
        <>
          <Table head={['Date', 'Demande', 'Professionnel', 'Signalé par', 'Commentaire']}>
            {data.items.map((r) => (
              <tr key={r.id}>
                <Cell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(r.createdAt)}</Cell>
                <Cell>
                  {r.request ? (
                    <a href={`#/requests/${r.request.id}`} className="font-semibold text-primary hover:underline">
                      {r.request.service ?? 'Demande'}{r.request.city ? ` · ${r.request.city}` : ''}
                    </a>
                  ) : '—'}
                </Cell>
                <Cell>
                  {r.pro ? (
                    <a href={`#/pros/${r.pro.userId}`} className="font-semibold text-primary hover:underline">{r.pro.name ?? r.pro.profession}</a>
                  ) : '—'}
                </Cell>
                <Cell>
                  <p>{r.reporter?.name ?? '—'}</p>
                  <p className="text-xs text-muted-foreground">{r.reporter?.phoneNumber ?? ''}</p>
                </Cell>
                <Cell className="max-w-sm">{r.comment ?? <span className="text-muted-foreground">sans commentaire</span>}</Cell>
              </tr>
            ))}
          </Table>
          <Pager page={data.page} totalPages={data.totalPages} onPage={setPage} />
        </>
      ) : null}
    </>
  );
}

import { useState } from 'react';
import { Card, Cell, Empty, ErrorNote, Loading, PageHeader, Table, Tabs } from '../components/ui';
import { api } from '../lib/api';
import { useLoad } from '../lib/useLoad';
import { fmtDateTime, pct } from '../lib/utils';

interface Gaps {
  totals: { searches: number; unfulfilled: number; fulfilmentRate: number };
  gaps: Array<{ term: string; count: number; lastSearchedAt: string | null }>;
}

const WINDOWS = [
  { value: '7', label: '7 jours' },
  { value: '30', label: '30 jours' },
  { value: '90', label: '90 jours' },
  { value: 'all', label: 'Depuis le début' },
];

/** What members ask for that no professional offers yet — who to recruit next. */
export function Gaps() {
  const [days, setDays] = useState('30');
  const { data, error, loading } = useLoad(() => {
    const from = days === 'all' ? undefined : new Date(Date.now() - Number(days) * 86_400_000).toISOString();
    return api<Gaps>('/data/admin/analytics/unfulfilled', { query: { from, limit: 50 } });
  }, [days]);

  return (
    <>
      <PageHeader
        title="Besoins non couverts"
        subtitle="Ce que les membres demandent et qu'aucun professionnel ne propose encore : les métiers à recruter."
        actions={<Tabs value={days} onChange={setDays} options={WINDOWS} />}
      />
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data ? (
        <>
          <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Card>
              <p className="text-3xl font-extrabold">{data.totals.searches}</p>
              <p className="text-sm font-semibold">Demandes analysées</p>
            </Card>
            <Card>
              <p className="text-3xl font-extrabold text-warning">{data.totals.unfulfilled}</p>
              <p className="text-sm font-semibold">Sans professionnel</p>
            </Card>
            <Card>
              <p className="text-3xl font-extrabold">{pct(data.totals.fulfilmentRate)}</p>
              <p className="text-sm font-semibold">Couvertes</p>
            </Card>
          </div>
          {data.gaps.length === 0 ? (
            <Empty>Aucun besoin non couvert sur cette période.</Empty>
          ) : (
            <Table head={['Besoin', 'Demandes', 'Dernière fois']}>
              {data.gaps.map((g) => (
                <tr key={g.term}>
                  <Cell className="font-semibold">{g.term}</Cell>
                  <Cell className="tabular-nums">{g.count}</Cell>
                  <Cell className="text-muted-foreground">{fmtDateTime(g.lastSearchedAt)}</Cell>
                </tr>
              ))}
            </Table>
          )}
        </>
      ) : null}
    </>
  );
}

import { useState } from 'react';
import { Badge, Cell, Empty, ErrorNote, Loading, PageHeader, Pager, Row, SearchInput, Table, Tabs } from '../components/ui';
import { api, type Page } from '../lib/api';
import { go } from '../lib/router';
import { useLoad } from '../lib/useLoad';
import { fmtDate } from '../lib/utils';

interface Feature {
  until: string | null;
  active: boolean;
}

export interface SubscriberRow {
  userId: string;
  name: string | null;
  phoneNumber: string | null;
  country: string | null;
  subscriptionTypes: string[];
  hasProProfile: boolean;
  pro: Feature | null;
  spotlight: Feature | null;
  lastLoginAt: string | null;
}

/** A paid feature as a dated badge: green while active, orange once expired. */
function FeatureBadge({ label, feature }: { label: string; feature: Feature | null }) {
  if (!feature) return null;
  return (
    <Badge tone={feature.active ? 'green' : 'orange'}>
      {label}
      {feature.until ? ` · ${feature.active ? "jusqu'au" : 'expiré le'} ${fmtDate(feature.until)}` : ''}
    </Badge>
  );
}

export function Subscribers() {
  const [type, setType] = useState<'' | 'pro' | 'spotlight'>('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const { data, error, loading } = useLoad(
    () => api<Page<SubscriberRow>>('/data/admin/subscribers', { query: { type, search, page, limit: 25 } }),
    [type, search, page],
  );

  return (
    <>
      <PageHeader
        title="Abonnés"
        subtitle="Membres ayant payé un produit sur SBC : Pro (2 000 F/mois) et mise en avant (3 000 F/mois)."
      />
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={search} onChange={(v) => (setSearch(v), setPage(1))} placeholder="Nom, téléphone, e-mail" />
        <Tabs
          value={type}
          onChange={(v) => (setType(v), setPage(1))}
          options={[
            { value: '', label: 'Tous' },
            { value: 'pro', label: 'Pro' },
            { value: 'spotlight', label: 'Mise en avant' },
          ]}
        />
      </div>
      {error ? <ErrorNote error={error} /> : loading && !data ? <Loading /> : data && data.items.length === 0 ? (
        <Empty>Aucun abonné pour le moment.</Empty>
      ) : data ? (
        <>
          <p className="mb-3 text-sm text-muted-foreground">
            <span className="font-bold tabular-nums text-foreground">{data.total}</span> abonné{data.total > 1 ? 's' : ''}
          </p>
          <Table head={['Membre', 'Pays', 'Abonnements', 'Dernière connexion']}>
            {data.items.map((u) => (
              <Row key={u.userId} onOpen={u.hasProProfile ? () => go(`/pros/${u.userId}`) : undefined}>
                <Cell>
                  <p className="font-semibold">{u.name ?? '—'}</p>
                  <p className="text-xs text-muted-foreground">{u.phoneNumber ?? ''}</p>
                </Cell>
                <Cell>{u.country ?? '—'}</Cell>
                <Cell>
                  <div className="flex flex-wrap gap-1.5">
                    <FeatureBadge label="Pro" feature={u.pro} />
                    <FeatureBadge label="Mise en avant" feature={u.spotlight} />
                  </div>
                </Cell>
                <Cell className="text-xs text-muted-foreground">{fmtDate(u.lastLoginAt)}</Cell>
              </Row>
            ))}
          </Table>
          <Pager page={data.page} totalPages={data.totalPages} onPage={setPage} />
        </>
      ) : null}
    </>
  );
}

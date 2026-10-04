import { useEffect, useState } from 'react';
import { Layout } from './components/Layout';
import { Loading } from './components/ui';
import { tokens } from './lib/api';
import { completeLoginFromUrl, currentUser, isAdmin, logout, applyDevToken, type AdminUser } from './lib/auth';
import { useRoute } from './lib/router';
import { Dashboard } from './pages/Dashboard';
import { Gaps } from './pages/Gaps';
import { Login } from './pages/Login';
import { ProDetail } from './pages/ProDetail';
import { Pros } from './pages/Pros';
import { Reports } from './pages/Reports';
import { RequestDetail } from './pages/RequestDetail';
import { Requests } from './pages/Requests';
import { Services } from './pages/Services';

type Session = { state: 'loading' } | { state: 'out'; error?: unknown; denied?: string | null } | { state: 'in'; user: AdminUser };

export function App() {
  const [session, setSession] = useState<Session>({ state: 'loading' });
  const route = useRoute();

  useEffect(() => {
    (async () => {
      try {
        applyDevToken();
        await completeLoginFromUrl();
        if (!tokens.get()) return setSession({ state: 'out' });
        const user = await currentUser();
        if (!isAdmin(user)) {
          tokens.clear();
          return setSession({ state: 'out', denied: user.name ?? 'Ce compte' });
        }
        setSession({ state: 'in', user });
      } catch (error) {
        tokens.clear();
        setSession({ state: 'out', error });
      }
    })();
  }, []);

  if (session.state === 'loading') return <div className="flex min-h-screen justify-center"><Loading /></div>;
  if (session.state === 'out') return <Login error={session.error} denied={session.denied} />;

  const [section = '', id] = route;
  const page = (() => {
    switch (section) {
      case 'requests': return id ? <RequestDetail id={id} /> : <Requests />;
      case 'pros': return id ? <ProDetail userId={id} /> : <Pros />;
      case 'services': return <Services />;
      case 'gaps': return <Gaps />;
      case 'reports': return <Reports />;
      default: return <Dashboard />;
    }
  })();

  return (
    <Layout section={section} user={session.user} onLogout={async () => (await logout(), setSession({ state: 'out' }))}>
      {page}
    </Layout>
  );
}

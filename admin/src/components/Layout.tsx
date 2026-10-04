import { ClipboardList, Flag, LayoutDashboard, LogOut, Tags, Users } from 'lucide-react';
import type { ReactNode } from 'react';
import type { AdminUser } from '../lib/auth';
import { cn } from '../lib/utils';

const NAV = [
  { path: '', label: 'Tableau de bord', icon: LayoutDashboard },
  { path: 'requests', label: 'Demandes', icon: ClipboardList },
  { path: 'pros', label: 'Professionnels', icon: Users },
  { path: 'services', label: 'Services', icon: Tags },
  { path: 'reports', label: 'Signalements', icon: Flag },
];

export function Layout({ section, user, onLogout, children }: {
  section: string;
  user: AdminUser;
  onLogout: () => void;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen md:flex">
      <aside className="border-b border-border bg-card md:sticky md:top-0 md:h-screen md:w-64 md:shrink-0 md:border-b-0 md:border-r">
        <div className="flex items-center gap-3 px-5 py-5">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="SBC Network" className="h-9 w-auto" />
          <span className="rounded-md bg-primary-soft px-2 py-0.5 text-xs font-bold text-primary">Admin</span>
        </div>
        <div className="mx-5 h-1 rounded-full bg-gradient-to-r from-primary via-brand-green to-brand-orange" aria-hidden />
        <nav aria-label="Navigation" className="flex gap-1 overflow-x-auto px-3 py-4 md:flex-col">
          {NAV.map(({ path, label, icon: Icon }) => (
            <a
              key={path}
              href={`#/${path}`}
              aria-current={section === path ? 'page' : undefined}
              className={cn(
                'flex shrink-0 items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-semibold transition-colors',
                section === path ? 'bg-primary-soft text-primary' : 'text-muted-foreground hover:bg-muted hover:text-foreground',
              )}
            >
              <Icon className="h-4 w-4" aria-hidden />
              {label}
            </a>
          ))}
        </nav>
        <div className="hidden px-5 py-4 md:absolute md:bottom-0 md:block md:w-64">
          <p className="truncate text-sm font-bold">{user.name ?? 'Administrateur'}</p>
          <p className="truncate text-xs text-muted-foreground">{user.email ?? user.role}</p>
          <button onClick={onLogout} className="mt-3 flex cursor-pointer items-center gap-2 text-sm font-semibold text-destructive hover:underline">
            <LogOut className="h-4 w-4" aria-hidden /> Se déconnecter
          </button>
        </div>
      </aside>
      <main className="min-w-0 flex-1 px-4 py-6 md:px-10 md:py-8">
        <div className="mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}

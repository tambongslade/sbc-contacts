import { ShieldCheck } from 'lucide-react';
import { Button, ErrorNote } from '../components/ui';
import { startLogin } from '../lib/auth';

export function Login({ error, denied }: { error?: unknown; denied?: string | null }) {
  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm rounded-lg border border-border bg-card p-8 text-center">
        <img src={`${import.meta.env.BASE_URL}logo.png`} alt="SBC Network" className="mx-auto h-14 w-auto" />
        <div className="mx-auto my-5 h-1 w-24 rounded-full bg-gradient-to-r from-primary via-brand-green to-brand-orange" aria-hidden />
        <h1 className="text-xl font-extrabold">Administration</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Demandes, professionnels, services et signalements de SBC Network.
        </p>
        {denied && (
          <p className="mt-5 rounded-lg bg-warning-soft px-4 py-3 text-sm font-semibold text-warning">
            {denied} n'a pas le rôle administrateur. Demande à un super-admin de te l'attribuer.
          </p>
        )}
        {error ? <div className="mt-5"><ErrorNote error={error} /></div> : null}
        <Button className="mt-6 w-full" onClick={startLogin}>
          <ShieldCheck className="h-4 w-4" aria-hidden /> Se connecter avec SBC
        </Button>
      </div>
    </div>
  );
}

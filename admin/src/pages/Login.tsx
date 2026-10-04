import { KeyRound, ShieldCheck } from 'lucide-react';
import { type FormEvent, useState } from 'react';
import { Button, ErrorNote, Field, inputCls } from '../components/ui';
import { loginWithPassword, startLogin } from '../lib/auth';

export function Login({ error, denied }: { error?: unknown; denied?: string | null }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<unknown>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setFormError(null);
    try {
      await loginWithPassword(email.trim(), password);
      // Re-run the app's auth check (fetch /auth/me, verify ADMIN role).
      window.location.reload();
    } catch (err) {
      setFormError(err);
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm rounded-lg border border-border bg-card p-8">
        <img
          src={`${import.meta.env.BASE_URL}logo.png`}
          alt="SBC Network"
          className="mx-auto h-14 w-auto"
        />
        <div
          className="mx-auto my-5 h-1 w-24 rounded-full bg-gradient-to-r from-primary via-brand-green to-brand-orange"
          aria-hidden
        />
        <h1 className="text-center text-xl font-extrabold">Administration</h1>
        <p className="mt-2 text-center text-sm text-muted-foreground">
          Demandes, professionnels, services et signalements de SBC Network.
        </p>

        {denied && (
          <p className="mt-5 rounded-lg bg-warning-soft px-4 py-3 text-sm font-semibold text-warning">
            {denied} n'a pas le rôle administrateur. Demande à un super-admin de te l'attribuer.
          </p>
        )}
        {error ? (
          <div className="mt-5">
            <ErrorNote error={error} />
          </div>
        ) : null}

        <form onSubmit={submit} className="mt-6 space-y-4">
          <Field label="Email">
            <input
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className={inputCls}
            />
          </Field>
          <Field label="Mot de passe">
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={inputCls}
            />
          </Field>
          {formError ? <ErrorNote error={formError} /> : null}
          <Button type="submit" className="w-full" busy={busy}>
            <KeyRound className="h-4 w-4" aria-hidden /> Se connecter
          </Button>
        </form>

        <div className="my-5 flex items-center gap-3 text-xs text-muted-foreground">
          <span className="h-px flex-1 bg-border" aria-hidden /> ou{' '}
          <span className="h-px flex-1 bg-border" aria-hidden />
        </div>

        <Button variant="outline" className="w-full" onClick={startLogin}>
          <ShieldCheck className="h-4 w-4" aria-hidden /> Se connecter avec SBC
        </Button>
      </div>
    </div>
  );
}

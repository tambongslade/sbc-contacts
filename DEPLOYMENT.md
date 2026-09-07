# Deployment

The backend API is deployed at **https://contacts.sniperbusinesscenterlive.com**
(the Flutter app points here by default).

## Topology

```
Flutter app ──HTTPS──► nginx (contacts.sniperbusinesscenterlive.com, LetsEncrypt)
                         └─► http://localhost:3031  (pm2: sbc-contacts-api)
                                   ├─► Postgres  (docker: sbc_pg,    127.0.0.1:55432)
                                   └─► Redis      (docker: sbc_redis, 127.0.0.1:56379)
```

- **Process manager:** pm2 app `sbc-contacts-api` (`backend/ecosystem.config.js`),
  `NODE_ENV=production`, listening on `:3031`. `pm2 save` persists it across reboots.
- **Datastores:** two Docker containers with `--restart unless-stopped`
  (`sbc_pg` Postgres 16, `sbc_redis` Redis 7).
- **TLS:** Let's Encrypt via `certbot --nginx` (auto-renew scheduled). HTTP 301 → HTTPS.
- **Secrets:** live in `backend/.env` on the server (git-ignored). Strong JWT +
  AES-256-GCM encryption keys were generated at deploy time.

## Redeploy after a code change

```bash
cd /var/www/sbc-contacts/backend
git pull
npm ci && npx prisma migrate deploy && npm run build
pm2 restart sbc-contacts-api --update-env
```

## nginx vhost

`/etc/nginx/sites-available/contacts.sniperbusinesscenterlive.com`
(symlinked into `sites-enabled/`) — a plain reverse proxy to `localhost:3031`,
added alongside the existing sites without touching them.

## SSO status

The backend uses its **own dedicated SSO client** `sbc-contacts` (seeded on the SBC
platform). Registered redirect URIs:
`https://contacts.sniperbusinesscenterlive.com/auth/callback` **and**
`sbccontacts://auth/callback`; allowed scopes `profile.read, contacts.read`. Verified
against production SBC — a token exchange with a bad code returns SBC's real
`400 "Invalid … authorization code"` (a `401` would mean a bad client), so our client is
accepted and login works end-to-end with a real code. `contacts.read` is granted, so the
directory works after login.

### Mobile login flow (seamless, no manual paste)

1. App opens `https://sniperbuisnesscenter.com/sso/authorize` with
   `client_id=sbc-contacts`, `redirect_uri=https://contacts.sniperbusinesscenterlive.com/auth/callback`,
   `scope=profile.read contacts.read`.
2. After consent, SBC redirects the browser to our **callback bridge** —
   `GET /auth/callback` on this backend (mounted at the bare path, excluded from the
   `/api/v1` prefix). The bridge page redirects to `sbccontacts://auth/callback?code=...`
   (with a copy-code fallback).
3. The app receives the deep link (`app_links` + Android intent-filter), extracts the
   code, and calls `POST /api/v1/auth/sso-callback` to exchange it for a session.

If the secret is ever rotated (re-running the seed upserts by clientId), update
`SBC_SSO_CLIENT_SECRET` in `backend/.env` and `pm2 restart sbc-contacts-api`.

> Android App Links (the `https://` intent-filter, `autoVerify`) will only auto-open
> the app once `/.well-known/assetlinks.json` (with the signed APK's SHA-256) is hosted
> on the domain. The `sbccontacts://` custom scheme works without that.

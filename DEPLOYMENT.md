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

## ⚠️ One manual step before SSO login works

The backend is running, but "Log in with SBC" needs a **real SBC client**. An SBC
operator must register this app and give us the client secret (see
`SSO_INTEGRATION_GUIDE.md`):

```bash
cd user-service   # on the SBC platform
npx ts-node src/scripts/seed-sso-client.ts \
  --clientId=sbc-contacts \
  --name="SBC Contacts" \
  --redirectUri=sbccontacts://auth/callback \
  --scope=profile.read --scope=contacts.read
```

Then put the printed secret into `backend/.env` as `SBC_SSO_CLIENT_SECRET=...` and
`pm2 restart sbc-contacts-api`. Until then, health/directory endpoints work but the
SSO code exchange will fail (placeholder secret).

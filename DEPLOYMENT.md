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

The backend currently **reuses SBC Live's registered SSO client** (`client_id=sbc-live`,
its secret, and redirect `https://sniperbusinesscenterlive.com/auth/callback`). Verified
against production SBC: a token exchange with a bad code returns SBC's real
`400 "Invalid … authorization code"` (a `401` would mean a bad client), so the client
credentials are accepted and **login works end-to-end** once a real authorization code
is presented.

**Two limitations of reusing the sbc-live client:**

1. **`contacts.read` is not granted to `sbc-live`** (its scopes are
   `profile.read payments.write referrals.read`). So login works, but the **directory /
   search feature returns `403 INSUFFICIENT_SCOPE`** until an SBC operator either adds
   `contacts.read` to the `sbc-live` client, or seeds a dedicated `sbc-contacts` client:
   ```bash
   cd user-service   # on the SBC platform
   npx ts-node src/scripts/seed-sso-client.ts \
     --clientId=sbc-contacts --name="SBC Contacts" \
     --redirectUri=<mobile-or-web-callback> \
     --scope=profile.read --scope=contacts.read
   ```
   Then set `SBC_SSO_CLIENT_ID` / `SBC_SSO_CLIENT_SECRET` in `backend/.env` and
   `pm2 restart sbc-contacts-api`.

2. **The redirect_uri is a web URL**, not a mobile deep link. The app's manual
   "J'ai un code" entry works today; a seamless mobile flow needs the deep link
   (`sbccontacts://auth/callback`) registered as an allowed redirect for the client.

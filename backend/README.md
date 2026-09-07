# SBC Contacts — Backend

NestJS backend for the **SBC Contacts** mobile app. It is an **SSO client of
SBC** (it does not own the member database) plus a value-add layer that owns
saved sync criteria, favorites, sync history, notifications and the background
matching pipeline.

> Identity is delegated to SBC via "Log in with SBC" (see `../SSO_INTEGRATION_GUIDE.md`).
> This service exchanges the SSO code for SBC tokens, stores them **encrypted**,
> and issues its own app session (JWT + rotating refresh) to the Flutter client.

## Architecture at a glance

```
Flutter app ─► this backend ─► SBC (SSO + /api/contacts/sso/* directory)
                    │ owns: users, criteria, favorites, sync, notifications
                    │ mirrors: SBC members (cache-through + future webhook/bulk)
```

Member search/export are **proxied** to SBC per-user; results hydrate a local
`Member` mirror used for fast filtering and criteria matching.

## Stack

NestJS · TypeScript (strict) · PostgreSQL + Prisma · Redis · BullMQ · Swagger ·
Jest · Docker Compose.

## Getting started (local, without Docker)

```bash
cd backend
cp .env.example .env.development     # then fill in secrets
npm install
npm run prisma:generate
npm run prisma:migrate               # needs a running Postgres
npm run start:dev
```

- API:      http://localhost:3001/api/v1
- Swagger:  http://localhost:3001/api/docs
- Health:   http://localhost:3001/api/v1/health/ready

> The app defaults to **port 3001** (3000 is commonly taken). Change `PORT` in `.env`.

## Getting started (Docker)

```bash
cp .env.example .env                 # compose reads .env
docker compose up --build
```

Brings up `postgres`, `redis`, `api` (runs migrations on boot) and a `worker`
placeholder.

## Configuration

All config is env-driven and **validated at boot** — the app refuses to start
with missing/invalid variables. See `.env.example` for the full contract.
Nothing reads `process.env` directly except `src/config`.

## Project layout

```
src/
├── config/           validated env + namespaced configuration
├── common/           filters, interceptors, dtos, decorators (cross-cutting)
├── infrastructure/   prisma, cache (redis), queue (bullmq)
├── modules/          feature modules (health now; auth/directory/sync next)
├── app.module.ts
└── main.ts
prisma/schema.prisma  data model (app-owned tables + SBC member mirror)
```

## Roadmap (phases)

1. **Foundation** ✅ — config, Prisma, Redis, BullMQ, global pipes/filters/logging, Swagger, health, Docker.
2. **Auth (SSO)** ✅ — sbc-client, `/auth/sso-callback`, app JWT + rotating refresh (reuse detection), encrypted SBC-token store, RBAC guards.
3. **Directory** ✅ — search/filter/profile proxy + Redis cache; Member mirror hydration; favorites; VCF export.
4. **Sync** ✅ — criteria CRUD + live preview; sync runs with dedup; synced-contact state; summary/history; audit trail.
5. **Matching + notifications** ✅ — signature-verified webhook receiver (idempotent), BullMQ matching worker, notification provider abstraction + in-app store + device registry, "who added me".
6. **Hardening** — broader tests, tightened rate limits, deeper monitoring, security review. Then the Flutter app.

All of phases 1–5 are verified end-to-end against real Postgres + Redis (see `test/` and the module specs). 34 routes, 17 unit tests.
```

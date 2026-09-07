# SBC Contacts

Monorepo for **SBC Contacts** — a mobile app that turns the existing SBC member
base into an intelligent contact network on the phone
(*"Ton réseau SBC, directement dans ton téléphone."*).

The app lets an SBC member search the SBC directory, filter, view profiles,
contact members on WhatsApp, add them to the phone's address book, and
**intelligently synchronise** contacts matching saved criteria — with
notifications when new matching members appear.

## Structure

```
sbc-contacts/
├── backend/   NestJS API — SSO client of SBC + value-add layer
│              (auth, directory proxy + Member mirror, favorites, sync,
│               webhook-driven matching, notifications). PostgreSQL · Prisma ·
│               Redis · BullMQ · Swagger · Jest.
├── app/       Flutter app — Material 3 (SBC brand), Riverpod, Dio, go_router;
│              native contacts + WhatsApp deep-link integration.
└── SSO_INTEGRATION_GUIDE.md   How "Log in with SBC" works (contract with SBC).
```

## Architecture in one line

The backend is an **SSO client of SBC** — it never owns the member database; it
proxies SBC's per-member directory and adds the app-specific layer (saved
criteria, favorites, sync state, notifications). The Flutter app talks only to
this backend; SBC tokens live server-side, encrypted.

## Getting started

- **Backend:** see [`backend/README.md`](backend/README.md).
  `cd backend && cp .env.example .env.development && npm install && npm run prisma:migrate && npm run start:dev`
- **App:** `cd app && flutter pub get && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3030/api/v1`

## Tests

- Backend: `cd backend && npm test` (Jest — auth rotation, matching, SBC client).
- App unit/widget: `cd app && flutter test`.
- App ↔ backend integration (needs the backend running locally):
  `cd app && flutter test test/backend_integration_test.dart --tags integration --dart-define=API_BASE_URL=http://localhost:3030/api/v1`

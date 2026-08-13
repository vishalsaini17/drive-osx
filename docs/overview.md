# System Overview

**Read this first.** It is the shortest path to understanding Drive OSX well
enough to change it safely. When you need more depth, each section says where
to go.

| You want | Read |
| -------- | ---- |
| Why the system is shaped this way (the standing brief) | [CLAUDE.md](../CLAUDE.md) |
| How it is actually built | [Architecture](architecture.md) |
| How to run it | [README](../README.md) |
| What each application is and whether it works | [Application Inventory](reference/applications.md) |
| What talks to what | [Integration Map](reference/integration-map.md) |
| Known defects and gaps | [Audit and Plan](status/audit-and-plan.md) |
| How to test a change | [Testing](guides/testing.md) |
| Why a decision was made | [Decision records](architecture/decisions/) |
| How to work in this repo | [Developer Guide](guides/developer-guide.md) |

---

## 1. What the system does

Drive OSX presents a **browser-based operating environment**: a desktop with a
window manager, dock, launcher and command surfaces, inside which integrated
applications run — Files, Messenger, Contacts, Mail, Meet, editors, and more.

It is not a dashboard with tabs. Applications consume shared platform
capabilities (`platform.files`, `platform.windows`, `platform.contacts`, …)
rather than reaching for HTTP endpoints or storage keys themselves, so an
implementation can move without every application changing.

## 2. Repository structure

```text
drive-osx/
├── drive-osx-ui/          React 19 + TypeScript shell and applications
├── drive-osx-api/         Express modular monolith + background worker
├── drive-osx-mail/        SMTP gateway (holds no state of its own)
├── docs/                  architecture, feature docs, decision records
├── tests/e2e/             HTTP workflow probes against a running stack
├── scripts/               env drift check, git hooks
└── docker-compose*.yml    the whole stack, dev and production shapes
```

## 3. Services

| Service | Runtime | Responsibility |
| ------- | ------- | -------------- |
| `drive-osx-ui` | Vite / nginx | The desktop shell and every application |
| `drive-osx-api` | Node + Express | All domain logic and the only writer to PostgreSQL |
| `drive-osx-worker` | Node | Domain-event handlers and queued jobs |
| `drive-osx-mail` | Node SMTP | Accepts inbound mail, relays it to the API |
| `postgres` | PostgreSQL 17 | System of record |
| `redis` | Redis | Cache, queue, ephemeral realtime state |
| `minio` | S3-compatible | File bytes, versions, previews |

## 4. Databases

**PostgreSQL is the source of truth.** Redis holds nothing that cannot be
rebuilt. Object storage holds bytes; PostgreSQL holds the metadata that points
at them. The browser's IndexedDB is an offline cache and a queue of pending
operations, never an authority.

Schema is forward-only SQL in
`drive-osx-api/src/infrastructure/database/migrations/`, applied in filename
order inside one transaction each, with checksums — **an applied migration is
immutable; change the schema by adding a file.**

| Migration | Adds |
| --------- | ---- |
| `0001` | users, organizations, memberships, teams, sessions |
| `0002` | files, versions, shares, storage accounting |
| `0003` | mail, meetings, notifications, audit, `domain_events` |
| `0004` | chat requests, conversations, messages, contacts, presence |
| `0005` | contact detail fields (address, website, birthday, labels …) |

## 5. APIs

Everything lives under `/api/v1`. Routes are mounted in
[`drive-osx-api/src/app.ts`](../drive-osx-api/src/app.ts), which is the fastest way
to see the whole surface.

```text
/register /login /profile /auth/*     identity
/organizations  (/workspaces alias)   tenants, members, teams
/files /shares                        drive
/mail                                 mailboxes
/meetings                             meetings
/messaging                            chat requests, conversations, messages
/contacts                             address book + presence
/notifications /search /audit-logs    platform services
```

Interactive documentation is served at `/api/docs` outside production.

## 6. Authentication

Access token (JWT, 1h) + refresh token (opaque, 30d, rotated on use, stored
only as a SHA-256 hash). The client holds both in `localStorage` and refreshes
transparently through `platform/api/http.ts`.

Two endpoints authenticate a *service* rather than a user —
`POST /mail/receive` and `POST /mail/auth` — using the shared
`MAIL_GATEWAY_TOKEN`. See §"The SMTP gateway is a credentialled caller" in
[Architecture](architecture.md).

## 7. Authorization

**Server-side, always.** `platform/authorization/access-control.ts` is the only
place that decides whether an actor may touch a resource. Frontend checks exist
to shape the UI and are never the control.

The tenant for a request comes from the session (or `X-Organization-Id`,
validated against membership) — never from the request body. Denied access is
reported as `404`, not `403`, so the API does not confirm that a resource
exists.

**The trap:** every user registers into their own `personal` organization, so
organization scoping is the *wrong* boundary for anything social. Read
§"Every user starts alone in their own tenant" in
[Architecture](architecture.md) before touching messaging,
contacts or presence.

## 8. Integrations

Full table in [Integration Map](reference/integration-map.md). The shapes:

```text
Browser → API → PostgreSQL / object storage / Redis
API → domain_events (same transaction) → Worker → notifications, jobs
Internet → SMTP gateway → API /mail/receive → mailbox
Browser ↔ WebSocket gateway → Redis pub/sub → other browsers
```

## 9. Background jobs

State changes write to `domain_events` **in the same transaction** as the
change (transactional outbox). The worker claims batches with
`FOR UPDATE SKIP LOCKED` and marks an event processed only when every handler
succeeded. Delivery is at-least-once, so **handlers must be idempotent.**

Events → handlers: file indexing, preview generation, object purging, and
notifications for shares, mail, registration, workspace joins, and chat
requests/acceptances/messages.

## 10. Important workflows

Documented step by step in [Feature guides](features/). Two are worth reading
before touching the areas they cover:

* [messaging and contacts](features/messaging-and-contacts.md) — because it
  deliberately crosses tenant boundaries.
* [windows and the dock](features/shell-windows-and-dock.md) — because the
  obvious way to implement window dragging re-renders the whole desktop on
  every pointer move, and did once bring it down entirely. The rule: a pointer
  gesture never writes to the shell store while the pointer is down.

## 11. Environment configuration

Four `.env` files — root (Compose), API, mail, UI — each with a committed
`.env.example` that is the **only** description of what a service needs.

> Changing a `.env` or a config schema means changing the matching
> `.env.example` in the same commit. Verify with `./scripts/check-env.sh`.

Required with no default: `DATABASE_URL`, `REDIS_URL`, `STORAGE_*`,
`JWT_SECRET`, and `MAIL_GATEWAY_TOKEN` in production.

## 12. Local development

```sh
./scripts/check-env.sh --fix   # create .env files from templates
docker compose up -d           # dev stack: watch mode, ports published
```

UI on `:3000`, API on `:3001`, SMTP on `:1025`, MinIO console on `:9001`.

## 13. Testing

```sh
cd drive-osx-api && npm test          # 61 unit tests
./tests/e2e/platform-workflows.sh     # identity, files, sharing, trash, mail
./tests/e2e/messaging-and-contacts.sh # cross-tenant messaging, contacts, presence
```

`drive-osx-ui` has **no tests** — a known gap, see [Testing](guides/testing.md).

## 14. Deployment

`COMPOSE_FILE` switches between the development and production stacks; see
README §"Choosing development or production". Production uses compiled images,
nginx serving the shell, and datastores kept off the host network.

## 15. Monitoring and logging

Structured Pino logs carrying a request id through every layer; `/health` and
`/health/ready` on the API (readiness actually checks PostgreSQL and Redis);
the worker exposes its own health port reporting queue depth and event backlog.

## 16. Common problems

| Symptom | Cause |
| ------- | ----- |
| API will not start, "MAIL_GATEWAY_TOKEN required" | Production without the shared secret set — generate with `openssl rand -hex 32` and set it in **both** API and mail `.env`. |
| Mail delivery returns 401 | The two `MAIL_GATEWAY_TOKEN` values differ. |
| "Migration has changed since it was applied" | An applied migration file was edited. Revert it and add a new one. |
| A user cannot find anyone in Messenger | Substring search only spans shared organizations. Search the **exact** username or email. |
| A new env var works locally, breaks in CI | It was added to `.env` but not `.env.example`. Run `./scripts/check-env.sh`. |

## 17. Important architectural decisions

Recorded in [Decision records](architecture/decisions/).
Read the relevant record before reversing something — each explains what
breaks if you do.
